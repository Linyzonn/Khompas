import 'package:flutter/material.dart';

import '../ai_extractor.dart';
import '../models.dart';
import '../store.dart';
import 'dialogs.dart';

/// Verification humaine AVANT l'ajout : l'IA propose, tu disposes.
class VerifyScreen extends StatefulWidget {
  final ExtractionResult result;
  const VerifyScreen({super.key, required this.result});

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  late List<Colle> colles;

  @override
  void initState() {
    super.initState();
    colles = List.of(widget.result.colles);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Vérifie tes ${colles.length} khôlles')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          if (widget.result.avertissements.isNotEmpty)
            Card(
              margin: const EdgeInsets.all(12),
              color: Colors.amber.shade100,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.warning_amber, size: 18),
                        SizedBox(width: 6),
                        Text("Points à vérifier signalés par l'IA :",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    for (final w in widget.result.avertissements)
                      Text('• $w', style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
          for (var i = 0; i < colles.length; i++) _tile(context, i),
          Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un créneau manquant'),
              onPressed: () async {
                final c = await editColleDialog(context);
                if (c != null) {
                  setState(() {
                    colles.add(c);
                    colles.sort((a, b) => a.start.compareTo(b.start));
                  });
                }
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            icon: const Icon(Icons.check),
            label: Text('Ajouter ces ${colles.length} khôlles à mon agenda'),
            onPressed: colles.isEmpty
                ? null
                : () {
                    final added = AppModel.instance.addColles(colles);
                    final ignores = colles.length - added;
                    Navigator.popUntil(context, (r) => r.isFirst);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                        '$added khôlle(s) ajoutée(s)'
                        '${ignores > 0 ? ' · $ignores doublon(s) ignoré(s)' : ''} ✅',
                      ),
                    ));
                  },
          ),
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, int i) {
    final c = colles[i];
    final color = Color(subjectColor(c.matiere));
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.18),
        child: Text(
          c.matiere.isEmpty ? '?' : c.matiere.characters.first.toUpperCase(),
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text('${c.matiere}${c.kholleur.isEmpty ? '' : ' · ${c.kholleur}'}'),
      subtitle: Text(
        '${frDate(c.start)} · ${frHeure(c.start)}'
        '${c.salle.isEmpty ? '' : ' · salle ${c.salle}'}',
      ),
      onTap: () async {
        final edited = await editColleDialog(context, initial: c);
        if (edited != null) {
          setState(() {
            colles[i] = edited;
            colles.sort((a, b) => a.start.compareTo(b.start));
          });
        }
      },
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: () => setState(() => colles.removeAt(i)),
      ),
    );
  }
}
