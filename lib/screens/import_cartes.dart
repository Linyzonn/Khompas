import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai_extractor.dart';
import '../models.dart';
import '../store.dart';

/// Import EN MASSE du voc d'anglais ou des citations de francais, par
/// copier-coller avec son IA — le meme circuit gratuit que le programme
/// officiel : prompt copie -> feuille/notes dans ChatGPT, Claude ou Gemini
/// (photo, PDF ou texte) -> reponse collee ici -> verification -> ajout.
class ImportCartesScreen extends StatefulWidget {
  /// true = voc d'anglais, false = citations de francais.
  final bool vocabulaire;
  const ImportCartesScreen({super.key, required this.vocabulaire});

  @override
  State<ImportCartesScreen> createState() => _ImportCartesScreenState();
}

class _ImportCartesScreenState extends State<ImportCartesScreen> {
  List<MotVocab>? motsTrouves;
  List<Citation>? citationsTrouvees;
  List<String> avertissements = [];

  void _snack(String msg, {int secondes = 4}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: Duration(seconds: secondes),
      content: Text(msg),
    ));
  }

  Future<void> _copierPrompt() async {
    await Clipboard.setData(ClipboardData(
        text: widget.vocabulaire
            ? buildPromptVocab()
            : buildPromptCitations()));
    if (!mounted) return;
    _snack(
        'Prompt copié ✅ Ouvre ChatGPT, Claude ou Gemini : colle le prompt AVEC '
        '${widget.vocabulaire ? 'ta feuille de voc (photo, PDF ou texte copié)' : 'tes notes de français (photo, PDF ou texte copié)'}, '
        'puis copie toute sa réponse et reviens la coller ici.',
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
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: widget.vocabulaire
                  ? 'Colle ici la réponse complète (le bloc {"vocab": …}).'
                  : 'Colle ici la réponse complète (le bloc {"citations": …}).',
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
      if (widget.vocabulaire) {
        final result = parseVocabExtraction(raw);
        if (result.mots.isEmpty) {
          _snack('Aucun mot trouvé dans cette réponse.');
          return;
        }
        setState(() {
          motsTrouves = result.mots;
          avertissements = result.avertissements;
        });
      } else {
        final result = parseCitationsExtraction(raw);
        if (result.citations.isEmpty) {
          _snack('Aucune citation trouvée dans cette réponse.');
          return;
        }
        setState(() {
          citationsTrouvees = result.citations;
          avertissements = result.avertissements;
        });
      }
    } catch (_) {
      _snack(
          "Réponse illisible — copie bien TOUTE la réponse de l'IA, accolades comprises.",
          secondes: 6);
    }
  }

  @override
  Widget build(BuildContext context) {
    final voc = widget.vocabulaire;
    final mots = motsTrouves;
    final cits = citationsTrouvees;
    final nb = voc ? (mots?.length ?? 0) : (cits?.length ?? 0);
    return Scaffold(
      appBar: AppBar(
          title: Text(voc
              ? 'Importer ma feuille de voc'
              : 'Importer mes citations')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                voc
                    ? 'Ta feuille de voc entière en 1 minute :\n'
                        '1. Copie le prompt.\n'
                        '2. Dans ton appli d\'IA (ChatGPT, Claude, Gemini), colle le prompt et joins la PHOTO ou le PDF de ta feuille (ou colle son texte).\n'
                        '3. Copie toute sa réponse et reviens la coller ici.\n'
                        'Les doublons sont ignorés — tu peux importer plusieurs feuilles.'
                    : 'Ta fiche de citations entière en 1 minute :\n'
                        '1. Copie le prompt.\n'
                        '2. Dans ton appli d\'IA, colle le prompt et joins tes notes de français (photo, PDF ou texte).\n'
                        '3. Copie toute sa réponse et reviens la coller ici.\n'
                        'Chaque citation arrive avec auteur, axe du thème et « comment l\'utiliser ». Les doublons sont ignorés.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
              ),
            ),
          ),
          const SizedBox(height: 12),
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
          if (nb > 0) ...[
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
            Text('Vérifie ($nb) :',
                style: Theme.of(context).textTheme.titleMedium),
            if (voc)
              for (final v in mots!)
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: Text('${v.francais} → ${v.anglais}',
                      style: const TextStyle(fontSize: 13)),
                  subtitle: v.remarque.isEmpty
                      ? null
                      : Text(v.remarque, style: const TextStyle(fontSize: 11)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => setState(() => mots.remove(v)),
                  ),
                )
            else
              for (final c in cits!)
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: Text('« ${c.texte} »',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                      [
                        if (c.auteur.isNotEmpty) c.auteur,
                        if (c.axe.isNotEmpty) c.axe,
                      ].join(' · '),
                      style: const TextStyle(fontSize: 11)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => setState(() => cits.remove(c)),
                  ),
                ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.check),
              label: Text(voc
                  ? 'Ajouter ces $nb mots'
                  : 'Ajouter ces $nb citations'),
              onPressed: nb == 0
                  ? null
                  : () {
                      final m = AppModel.instance;
                      final added = voc
                          ? m.addVocabList(mots!)
                          : m.addCitationsList(cits!);
                      final doublons = nb - added;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                          '$added ajouté(s)'
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
