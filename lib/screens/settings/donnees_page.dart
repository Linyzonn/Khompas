import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../api_client.dart';
import '../../store.dart';
import '../../theme.dart';

/// Sous-page Reglages : sauvegarde/restauration, remise a zero complete,
/// serveur Khompas et cle API personnelle.
class DonneesPage extends StatefulWidget {
  const DonneesPage({super.key});

  @override
  State<DonneesPage> createState() => _DonneesPageState();
}

class _DonneesPageState extends State<DonneesPage> {
  late final TextEditingController serverCtl;
  late final TextEditingController keyCtl;
  // Une copie de secours (.corrompu) existe-t-elle sur cet appareil ?
  bool copieSecoursExiste = false;

  @override
  void initState() {
    super.initState();
    final m = AppModel.instance;
    serverCtl = TextEditingController(text: m.serverUrl);
    keyCtl = TextEditingController(text: m.apiKey);
    m.lireCopieSecours().then((raw) {
      if (mounted && raw != null && raw.trim().isNotEmpty) {
        setState(() => copieSecoursExiste = true);
      }
    });
  }

  @override
  void dispose() {
    serverCtl.dispose();
    keyCtl.dispose();
    super.dispose();
  }

  void _snack(String msg, {int secondes = 4}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: Duration(seconds: secondes),
      content: Text(msg),
    ));
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
      setState(() {});
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

  // ---------- Copie de secours (.corrompu) ----------

  Future<void> _restaurerSecours() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Récupérer la copie de secours ?'),
        content: const Text(
            'La copie créée quand des données étaient illisibles sera '
            'restaurée (réparée automatiquement si sa fin est tronquée). '
            'Les données ACTUELLES de l\'appareil seront remplacées.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Récupérer')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final resume = await AppModel.instance.restaurerCopieSecours();
      if (mounted) _snack('Copie de secours restaurée ✅ ($resume)', secondes: 7);
    } catch (e) {
      if (mounted) {
        _snack(
            'Récupération impossible : ${e.toString().replaceFirst('Exception: ', '')}',
            secondes: 8);
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _exporterSecours() async {
    final raw = await AppModel.instance.lireCopieSecours();
    if (raw == null || raw.trim().isEmpty) {
      if (mounted) _snack('Aucune copie de secours sur cet appareil.');
      return;
    }
    try {
      if (kIsWeb) {
        await Clipboard.setData(ClipboardData(text: raw));
        if (mounted) {
          _snack(
              'Copie brute dans le presse-papiers ✅ Colle-la dans un fichier texte pour la réparer ou demander de l\'aide.',
              secondes: 7);
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/khompas-copie-secours.json');
      await f.writeAsString(raw);
      await Share.shareXFiles(
        [XFile(f.path, mimeType: 'application/json')],
        text:
            'Copie de secours Khompas (données brutes) — à garder pour réparation.',
      );
    } catch (e) {
      if (mounted) _snack('Échec de l\'export : $e');
    }
  }

  // ---------- Remise a zero ----------

  Future<void> _remettreAZero() async {
    final m = AppModel.instance;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Repartir de zéro ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tout ce qui est sur CET appareil sera effacé :\n'
              '• khôlles, DS et notes\n'
              '• chapitres, révisions et heures de travail\n'
              '• emploi du temps, calendrier, agenda\n'
              '• cahier d\'erreurs, annales, œuvres, oraux\n'
              '• profil, priorités, clé API et réglages',
              style: TextStyle(fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 10),
            if (m.compteCle.isNotEmpty) ...[
              Text(
                'Ton compte en ligne N\'EST PAS supprimé : le serveur garde sa '
                'dernière copie, récupérable avec ta clé (« J\'ai déjà une clé » '
                'au prochain démarrage). Note-la maintenant :',
                style:
                    TextStyle(fontSize: 12.5, color: couleurSecondaire(context)),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(m.compteCle,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 13)),
                trailing: IconButton(
                  tooltip: 'Copier la clé',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: m.compteCle)),
                ),
              ),
            ] else
              Text(
                'Mode invité : il n\'existe AUCUNE copie en ligne. Fais '
                '« Sauvegarder » d\'abord si tu veux pouvoir revenir en arrière.',
                style:
                    TextStyle(fontSize: 12.5, color: couleurSecondaire(context)),
              ),
            if (m.chargementEchoue)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'La copie de secours créée au démarrage (données illisibles) '
                  'est conservée sur l\'appareil.',
                  style: TextStyle(
                      fontSize: 12.5, color: couleurSecondaire(context)),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Tout effacer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await AppModel.instance.reinitialiser();
    if (!mounted) return;
    // Vide la pile (Reglages -> Donnees) : le Gate affiche deja l'onboarding.
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  // ---------- Suppression de la classe (createur uniquement) ----------

  Future<void> _supprimerClasse() async {
    final m = AppModel.instance;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Supprimer la classe ${m.codeClasse} ?'),
        content: const Text(
            'Tes camarades ne pourront plus importer avec ce code. Cette action est immédiate et définitive côté serveur (tes khôlles déjà importées restent dans l\'app de chacun).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ApiKhompas(m.serverUrl)
          .supprimerClasse(m.codeClasse, m.gestionClasse);
      m.setCodeClasse('');
      m.setGestionClasse('');
      _snack('Classe supprimée du serveur ✅');
    } catch (e) {
      _snack(
          'Échec : ${e.toString().replaceFirst('Exception: ', '')}');
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Données & avancé')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Mes données', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Tout est stocké sur cet appareil (téléphone, ou navigateur pour la '
            'version web). La sauvegarde sert aussi à passer tes données d\'un '
            'appareil à l\'autre. Sur iPhone en AltStore (compte Apple gratuit), '
            'l\'app peut expirer : sauvegarde régulièrement pour ne jamais perdre '
            'ton semestre — colloscope, notes et chapitres compris.',
            style: TextStyle(color: couleurSecondaire(context), fontSize: 12),
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
          if (copieSecoursExiste || AppModel.instance.chargementEchoue) ...[
            const SizedBox(height: 24),
            Text('Copie de secours',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Une copie automatique a été créée quand des données étaient '
              'illisibles. Tu peux tenter de la restaurer (réparation '
              'automatique des fins de fichier tronquées), ou l\'exporter '
              'brute pour la réparer à la main.',
              style: TextStyle(color: couleurSecondaire(context), fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.healing_outlined),
                    label: const Text('Récupérer'),
                    onPressed: _restaurerSecours,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Exporter brute'),
                    onPressed: _exporterSecours,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Text('Repartir de zéro',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Efface tout ce qui est sur cet appareil et raffiche l\'écran de '
            'bienvenue. Ton compte en ligne, si tu en as un, n\'est pas supprimé.',
            style: TextStyle(color: couleurSecondaire(context), fontSize: 12),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.restart_alt),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              side: BorderSide(color: Theme.of(context).colorScheme.error),
            ),
            label: const Text('Tout effacer et repartir de zéro…'),
            onPressed: _remettreAZero,
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
            style: TextStyle(color: couleurSecondaire(context), fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: serverCtl,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'Serveur Khompas (URL)',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Enregistrer l\'URL du serveur',
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
          if (m.codeClasse.isNotEmpty && m.gestionClasse.isNotEmpty) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_forever, size: 18),
              label: Text('Supprimer ma classe ${m.codeClasse} du serveur'),
              onPressed: _supprimerClasse,
            ),
            Text(
              'Photos du colloscope, extractions et programmes partagés compris. (Les photos expirent de toute façon après ~4 mois.)',
              style: TextStyle(color: couleurSecondaire(context), fontSize: 11.5),
            ),
          ],
          // Sans serveur (ou si une cle est deja enregistree), on propose la
          // cle API personnelle en secours. Sinon : inutile, on masque.
          if (m.serverUrl.isEmpty || m.apiKey.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Sans serveur, deux autres options sur l\'écran d\'import : ta propre '
              'clé API Claude ci-dessous (console.anthropic.com → API keys, quelques '
              'centimes par import), ou l\'import GRATUIT par copier-coller avec ton '
              'appli d\'IA (ChatGPT, Claude, Gemini).',
              style: TextStyle(color: couleurSecondaire(context), fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: keyCtl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Clé API Anthropic (facultative)',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Enregistrer la clé API',
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
        ],
      ),
    );
  }
}
