import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai_extractor.dart';
import '../models.dart';
import '../store.dart';

/// Import du planning de DS par copier-coller avec son IA (gratuit) :
/// meme principe que le colloscope — prompt copie, photo/PDF joint dans
/// SON appli d'IA, reponse collee ici, verification avant ajout.
class ImportDsScreen extends StatefulWidget {
  const ImportDsScreen({super.key});

  @override
  State<ImportDsScreen> createState() => _ImportDsScreenState();
}

class _ImportDsScreenState extends State<ImportDsScreen> {
  List<Ds>? trouves;
  List<String> avertissements = [];

  void _snack(String msg, {int secondes = 4}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: Duration(seconds: secondes),
      content: Text(msg),
    ));
  }

  Future<void> _copierPrompt() async {
    await Clipboard.setData(ClipboardData(text: buildPromptDs()));
    if (!mounted) return;
    _snack(
        'Prompt copié ✅ Ouvre ChatGPT, Claude ou Gemini : joins la photo (ou le PDF) du planning de DS, colle le prompt, puis copie TOUTE sa réponse et reviens la coller ici.',
        secondes: 7);
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
              hintText: 'Colle ici la réponse complète (le bloc {"ds": …}).',
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
      final result = parseDsExtraction(raw);
      if (result.ds.isEmpty) {
        _snack('Aucun DS trouvé dans cette réponse.');
        return;
      }
      setState(() {
        trouves = result.ds;
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
    return Scaffold(
      appBar: AppBar(title: const Text('Importer un planning de DS')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Ton lycée distribue un planning de DS (souvent le samedi matin) ? '
                'Importe-le en une fois, gratuitement :\n'
                '1. Copie le prompt.\n'
                '2. Dans ton appli d\'IA (ChatGPT, Claude, Gemini), joins la photo ou le PDF du planning et colle le prompt.\n'
                '3. Copie toute sa réponse et reviens la coller ici.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
              ),
            ),
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
            Text('Vérifie tes ${t.length} DS :',
                style: Theme.of(context).textTheme.titleMedium),
            for (var i = 0; i < t.length; i++)
              ListTile(
                dense: true,
                leading: CircleAvatar(
                  backgroundColor:
                      Color(subjectColor(t[i].matiere)).withOpacity(0.18),
                  child: Icon(Icons.edit_document,
                      color: Color(subjectColor(t[i].matiere)), size: 18),
                ),
                title: Text('${t[i].titre} ${t[i].matiere}'),
                subtitle: Text(frDate(t[i].date)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => setState(() => t.removeAt(i)),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.check),
              label: Text('Ajouter ces ${t.length} DS à mon agenda'),
              onPressed: t.isEmpty
                  ? null
                  : () {
                      final added = AppModel.instance.addDsList(t);
                      final doublons = t.length - added;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                          '$added DS ajouté(s)'
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
