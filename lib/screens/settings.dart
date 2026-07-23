import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../store.dart';
import 'routines.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController keyCtl;
  late final TextEditingController serverCtl;
  late final TextEditingController groupeCtl;
  static const filieres = [
    'MPSI', 'PCSI', 'PTSI', 'MP2I', 'BCPST',
    'MP', 'PC', 'PSI', 'PT', 'MPI',
    'ECG', 'Hypokhâgne', 'Khâgne', 'Autre',
  ];

  @override
  void initState() {
    super.initState();
    final m = AppModel.instance;
    keyCtl = TextEditingController(text: m.apiKey);
    serverCtl = TextEditingController(text: m.serverUrl);
    groupeCtl = TextEditingController(text: m.groupe.toString());
  }

  // ---------- Sauvegarde / restauration ----------

  Future<void> _sauvegarder() async {
    try {
      if (kIsWeb) {
        // Pas de partage de fichier dans le navigateur : on copie le JSON,
        // a coller soi-meme dans un fichier khompas-sauvegarde.json.
        await Clipboard.setData(
            ClipboardData(text: AppModel.instance.exportJson()));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            duration: Duration(seconds: 7),
            content: Text(
                'Sauvegarde copiée ✅ Colle-la dans un fichier texte (ex. khompas-sauvegarde.json) et garde-le en lieu sûr.'),
          ));
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final f = File(
          '${dir.path}/khompas-sauvegarde-${now.year}-${two(now.month)}-${two(now.day)}.json');
      await f.writeAsString(AppModel.instance.exportJson());
      await Share.shareXFiles(
        [XFile(f.path, mimeType: 'application/json')],
        text:
            'Sauvegarde Khompas — garde ce fichier en lieu sûr (Fichiers, Drive, mail à toi-même…).',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Échec de la sauvegarde : $e')));
      }
    }
  }

  Future<void> _restaurer() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restaurer une sauvegarde ?'),
        content: const Text(
            'Toutes les données actuelles (khôlles, notes, chapitres, priorités) '
            'seront REMPLACÉES par celles du fichier choisi.\n\n'
            'La clé API n\'est pas concernée.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Choisir le fichier')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      // API file_picker v11 : methode statique (l'ancien FilePicker.platform
      // n'existe plus).
      final res = await FilePicker.pickFiles(withData: true);
      final bytes = res?.files.single.bytes;
      if (bytes == null) return; // annule par l'utilisateur
      final resume = AppModel.instance.importJson(utf8.decode(bytes));
      if (!mounted) return;
      setState(() {
        groupeCtl.text = AppModel.instance.groupe.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Données restaurées ✅ ($resume)')));
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Restauration impossible : $msg')));
      }
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Mon profil', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: filieres.contains(m.filiere) ? m.filiere : 'Autre',
            decoration: const InputDecoration(
                labelText: 'Filière', border: OutlineInputBorder()),
            items: [
              for (final f in filieres) DropdownMenuItem(value: f, child: Text(f)),
            ],
            onChanged: (v) {
              if (v != null) {
                m.setProfil(filiere: v, groupe: m.groupe);
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: groupeCtl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Numéro de groupe de colle', border: OutlineInputBorder()),
            onSubmitted: (v) {
              final g = int.tryParse(v);
              if (g != null) m.setProfil(filiere: m.filiere, groupe: g);
            },
          ),
          const SizedBox(height: 24),
          Text('Priorité des matières',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Pondère le plan de travail (coefficients aux concours, matière à rattraper…).',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 8),
          if (m.matieres.isEmpty)
            Text('Les matières apparaîtront après ton premier import.',
                style: TextStyle(color: Colors.grey.shade600)),
          for (final mat in m.matieres)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(mat)),
                  for (var p = 1; p <= 3; p++)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: ChoiceChip(
                        label: Text('${'★' * p}'),
                        selected: (m.prios[mat] ?? 2) == p,
                        onSelected: (_) {
                          m.setPrio(mat, p);
                          setState(() {});
                        },
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          Text('Ma semaine type', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.loop),
            title: const Text('Cours tardifs, sport, activités…'),
            subtitle: const Text(
                'Ce qui revient chaque semaine, affiché sur Aujourd\'hui'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const RoutinesScreen())),
          ),
          const SizedBox(height: 24),
          Text('Mes données', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Tout est stocké sur cet appareil (téléphone, ou navigateur pour la '
            'version web). La sauvegarde sert aussi à passer tes données d\'un '
            'appareil à l\'autre. Sur iPhone en AltStore (compte Apple gratuit), '
            'l\'app peut expirer : sauvegarde régulièrement pour ne jamais perdre '
            'ton semestre — colloscope, notes et chapitres compris.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Sauvegarder'),
                  onPressed: _sauvegarder,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.settings_backup_restore),
                  label: const Text('Restaurer'),
                  onPressed: _restaurer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Serveur Khompas & extraction IA',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Avec le serveur Khompas, ta classe partage son colloscope par un '
            'simple CODE : personne n\'a besoin de clé API. Colle ici l\'URL du '
            'serveur (ex. https://khompas.deno.dev) — la section « Code de '
            'classe » apparaîtra sur l\'écran d\'import.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: serverCtl,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'Serveur Khompas (URL)',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.save),
                onPressed: () async {
                  await m.saveServerUrl(serverCtl.text);
                  if (mounted) setState(() {});
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Serveur enregistré ✅')));
                  }
                },
              ),
            ),
          ),
          // Sans serveur (ou si une cle est deja enregistree), on propose la
          // cle API personnelle en secours. Sinon : inutile, on masque.
          if (m.serverUrl.isEmpty || m.apiKey.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Sans serveur, deux autres options sur l\'écran d\'import : ta propre '
              'clé API Claude ci-dessous (console.anthropic.com → API keys, quelques '
              'centimes par import), ou l\'import GRATUIT par copier-coller avec ton '
              'appli d\'IA (ChatGPT, Claude, Gemini).',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: keyCtl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Clé API Anthropic (facultative)',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.save),
                  onPressed: () async {
                    await m.saveApiKey(keyCtl.text);
                    if (mounted) setState(() {});
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Clé enregistrée ✅')));
                    }
                  },
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Khompas — bêta 0.5'),
            subtitle: Text(
                'Le compagnon de ta prépa. Tes données restent sur ton téléphone.'),
          ),
        ],
      ),
    );
  }
}
