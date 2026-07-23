import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai_extractor.dart';
import '../models.dart';
import '../store.dart';

/// Import des chapitres depuis le PROGRAMME OFFICIEL de la filiere
/// (prepa.org ou PDF officiel), par copier-coller avec son IA — gratuit.
class ImportChapitresScreen extends StatefulWidget {
  const ImportChapitresScreen({super.key});

  @override
  State<ImportChapitresScreen> createState() => _ImportChapitresScreenState();
}

class _ImportChapitresScreenState extends State<ImportChapitresScreen> {
  List<Chapitre>? trouves;
  List<String> avertissements = [];
  final matiereCtl = TextEditingController();
  // 5/2 : tout le programme a deja ete vu -> les chapitres arrivent
  // "vus en cours" avec une maitrise moyenne, au lieu de "pas vu".
  bool cinqDemi = false;

  static const _matieresCourantes = [
    'Maths', 'Physique', 'Chimie', 'SII', 'Informatique', 'Français', 'Anglais',
  ];

  void _snack(String msg, {int secondes = 4}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: Duration(seconds: secondes),
      content: Text(msg),
    ));
  }

  Future<void> _copierPrompt() async {
    final filiere = AppModel.instance.filiere;
    final mat = matiereCtl.text.trim();
    await Clipboard.setData(
        ClipboardData(text: buildPromptChapitres(filiere, matiere: mat)));
    if (!mounted) return;
    _snack(
        'Prompt copié ✅ ($filiere${mat.isEmpty ? '' : ' · $mat'}) Ouvre ChatGPT, Claude ou Gemini : colle le prompt AVEC le texte du programme (copié depuis prepa.org) ou joins le PDF officiel, puis copie toute sa réponse et reviens la coller ici.',
        secondes: 8);
  }

  Future<void> _collerReponse() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final clipText = clip?.text ?? '';
    final ctl =
        TextEditingController(text: clipText.contains('{') ? clipText : '');
    if (!mounted) return;
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Réponse de l'IA"),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: ctl,
            maxLines: 10,
            minLines: 5,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText:
                  'Colle ici la réponse complète (le bloc {"chapitres": …}).',
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctl.text),
              child: const Text('Analyser')),
        ],
      ),
    );
    if (raw == null || raw.trim().isEmpty || !mounted) return;
    try {
      final result = parseChapitresExtraction(raw);
      if (result.chapitres.isEmpty) {
        _snack('Aucun chapitre trouvé dans cette réponse.');
        return;
      }
      setState(() {
        trouves = result.chapitres;
        avertissements = result.avertissements;
      });
    } catch (_) {
      _snack(
          "Réponse illisible — copie bien TOUTE la réponse de l'IA, accolades comprises.",
          secondes: 6);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = trouves;
    final matieres = t == null
        ? const <String>[]
        : (t.map((c) => c.matiere).toSet().toList()..sort());
    return Scaffold(
      appBar: AppBar(title: const Text('Importer le programme officiel')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Sur prepa.org, les programmes officiels sont publiés MATIÈRE par '
                'matière. Choisis une matière ci-dessous, puis :\n'
                '1. Copie le prompt.\n'
                '2. Dans ton appli d\'IA, colle le prompt PUIS le texte du programme '
                'de cette matière (copié depuis prepa.org), ou joins le PDF.\n'
                '3. Copie toute sa réponse et reviens la coller ici.\n'
                'Répète pour chaque matière — les doublons sont ignorés.\n\n'
                '5/2 : colle les programmes de 1re ET 2e année si tu veux tout '
                'réviser (les concours portent sur les deux), et active '
                'l\'interrupteur 5/2 plus bas.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: matiereCtl,
            decoration: const InputDecoration(
              labelText: 'Matière du programme (recommandé)',
              helperText:
                  'Laisse vide seulement si ton document couvre plusieurs matières.',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              children: [
                for (final mat in {
                  ..._matieresCourantes,
                  ...AppModel.instance.matieres,
                })
                  ActionChip(
                    label: Text(mat, style: const TextStyle(fontSize: 12)),
                    onPressed: () => setState(() => matiereCtl.text = mat),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Je suis 5/2'),
            subtitle: const Text(
                'Les chapitres arrivent « vus en cours » avec une maîtrise moyenne, '
                'au lieu de « pas vu » — c\'est une année de révision, pas de découverte.'),
            value: cinqDemi,
            onChanged: (v) => setState(() => cinqDemi = v),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.copy_all),
            label: const Text('1. Copier le prompt'),
            onPressed: _copierPrompt,
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.content_paste_go),
            label: const Text("2. Coller la réponse de l'IA"),
            onPressed: _collerReponse,
          ),
          if (t != null) ...[
            const SizedBox(height: 16),
            if (avertissements.isNotEmpty)
              Card(
                color: Colors.amber.shade100,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Points à vérifier signalés par l'IA :",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      for (final w in avertissements)
                        Text('• $w', style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ),
            Text('Vérifie tes ${t.length} chapitres :',
                style: Theme.of(context).textTheme.titleMedium),
            for (final mat in matieres) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 2),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: Color(subjectColor(mat)),
                          shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(mat, style: Theme.of(context).textTheme.titleSmall),
                  ],
                ),
              ),
              for (final c in t.where((c) => c.matiere == mat).toList())
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: Text(c.nom, style: const TextStyle(fontSize: 13)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => setState(() => t.remove(c)),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.check),
              label: Text('Ajouter ces ${t.length} chapitres'),
              onPressed: t.isEmpty
                  ? null
                  : () {
                      // 5/2 : programme deja vu -> statuts de depart adaptes.
                      if (cinqDemi) {
                        for (final c in t) {
                          c.etape = 1; // vu en cours (l'an dernier)
                          c.maitrise = 2; // moyen — a re-evaluer en revisant
                        }
                      }
                      final added = AppModel.instance.addChapitresList(t);
                      final doublons = t.length - added;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                          '$added chapitre(s) ajouté(s)'
                          '${doublons > 0 ? ' · $doublons doublon(s) ignoré(s)' : ''} ✅',
                        ),
                      ));
                    },
            ),
          ],
        ],
      ),
    );
  }
}
