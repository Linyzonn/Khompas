import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api_client.dart';
import '../models.dart';
import '../notifs.dart';
import '../store.dart';
import 'annales.dart';
import 'calendrier.dart';
import 'edt.dart';
import 'oraux.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController keyCtl;
  late final TextEditingController serverCtl;
  late final TextEditingController groupeCtl;

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

  // ---------- Mode revisions concours ----------

  Future<void> _choisirConcours() async {
    final m = AppModel.instance;
    final d = await showDatePicker(
      context: context,
      initialDate:
          m.dateConcours ?? DateTime.now().add(const Duration(days: 60)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (d != null) {
      m.setDateConcours(DateTime(d.year, d.month, d.day));
      if (mounted) setState(() {});
    }
  }

  // ---------- Fusion de matieres ----------

  Future<void> _fusionnerDialog() async {
    final m = AppModel.instance;
    final liste = m.matieres;
    String? source;
    String? cible;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Fusionner deux matières'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButton<String>(
                value: source,
                isExpanded: true,
                hint: const Text('Matière à faire disparaître'),
                items: [
                  for (final mat in liste)
                    DropdownMenuItem(value: mat, child: Text(mat)),
                ],
                onChanged: (v) => setState(() => source = v),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Icon(Icons.arrow_downward, size: 18),
              ),
              DropdownButton<String>(
                value: cible,
                isExpanded: true,
                hint: const Text('Matière qui garde tout'),
                items: [
                  for (final mat in liste)
                    if (mat != source)
                      DropdownMenuItem(value: mat, child: Text(mat)),
                ],
                onChanged: (v) => setState(() => cible = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: source == null || cible == null || source == cible
                  ? null
                  : () {
                      m.fusionnerMatieres(source!, cible!);
                      Navigator.pop(context);
                      _snack('« $source » fusionnée dans « $cible » ✅');
                    },
              child: const Text('Fusionner'),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  // ---------- Heure limite de sommeil ----------

  Future<void> _choisirHeureLimite() async {
    final m = AppModel.instance;
    final actuel = m.heureLimiteMin ?? 23 * 60;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: actuel ~/ 60, minute: actuel % 60),
      helpText: 'Heure limite de travail le soir',
    );
    if (t != null) {
      m.setHeureLimite(t.hour * 60 + t.minute);
      if (mounted) setState(() {});
    }
  }

  // ---------- Compte ----------

  void _snack(String msg, {int secondes = 4}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: Duration(seconds: secondes),
      content: Text(msg),
    ));
  }

  String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<void> _creerCompte() async {
    final m = AppModel.instance;
    try {
      final cle = await ApiKhompas(m.serverUrl)
          .creerCompte(filiere: m.filiere, cinqDemi: m.cinqDemi);
      await m.saveCompteCle(cle);
      try {
        await m.pousserCompte();
      } catch (_) {
        // le push automatique reessaiera
      }
      if (!mounted) return;
      setState(() {});
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Ta clé de compte 🔑'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: SelectableText(
                  cle,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'NOTE-LA précieusement : c\'est elle — et elle seule — qui '
                'permet de retrouver tes données ailleurs. Elle reste visible '
                'ici (icône copier).',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: cle));
              },
              child: const Text('Copier'),
            ),
            FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('C\'est noté')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) _snack('Création impossible : ${_msg(e)}', secondes: 6);
    }
  }

  Future<void> _connecterCompte() async {
    final m = AppModel.instance;
    final ctl = TextEditingController();
    final cle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ma clé de compte'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
              border: OutlineInputBorder(), hintText: '18 caractères'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctl.text),
              child: const Text('Se connecter')),
        ],
      ),
    );
    if (cle == null || cle.trim().isEmpty || !mounted) return;
    try {
      final resume = await m.connecterCompte(cle);
      if (!mounted) return;
      setState(() {
        groupeCtl.text = m.groupe.toString();
      });
      _snack('Compte connecté ✅ ($resume)');
    } catch (e) {
      if (mounted) _snack('Connexion impossible : ${_msg(e)}', secondes: 6);
    }
  }

  Future<void> _pousser() async {
    try {
      await AppModel.instance.pousserCompte();
      if (mounted) _snack('Données envoyées au compte ✅');
    } catch (e) {
      if (mounted) _snack('Envoi impossible : ${_msg(e)}', secondes: 6);
    }
  }

  Future<void> _tirer() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Récupérer du compte ?'),
        content: const Text(
            'Les données de cet appareil seront REMPLACÉES par celles du compte '
            '(la dernière version envoyée, depuis n\'importe quel appareil).'),
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
      final resume = await AppModel.instance.tirerCompte();
      if (!mounted) return;
      setState(() {
        groupeCtl.text = AppModel.instance.groupe.toString();
      });
      _snack('Données récupérées ✅ ($resume)');
    } catch (e) {
      if (mounted) _snack('Récupération impossible : ${_msg(e)}', secondes: 6);
    }
  }

  Future<void> _dissocier() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dissocier cet appareil ?'),
        content: const Text(
            'Tes données restent sur cet appareil ET sur le compte — seule la '
            'clé locale est oubliée. Assure-toi de l\'avoir notée quelque part !'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Dissocier')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await AppModel.instance.deconnecterCompte();
    if (mounted) setState(() {});
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
            value: kFilieres.contains(m.filiere) ? m.filiere : 'Autre',
            decoration: const InputDecoration(
                labelText: 'Filière', border: OutlineInputBorder()),
            items: [
              for (final f in kFilieres) DropdownMenuItem(value: f, child: Text(f)),
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
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Je suis 5/2'),
            subtitle: const Text(
                'Je refais ma 2e année — adapte l\'import du programme (chapitres déjà vus).'),
            value: m.cinqDemi,
            onChanged: (v) {
              m.setCinqDemi(v);
              setState(() {});
            },
          ),
          const SizedBox(height: 24),
          Text('Compte', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          if (m.serverUrl.isEmpty)
            Text(
              'Renseigne d\'abord l\'URL du serveur (plus bas) pour activer les comptes.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            )
          else if (m.compteCle.isEmpty) ...[
            Text(
              'Un compte = tes données sauvegardées en ligne et synchronisées '
              'entre ton téléphone et ton PC. Gratuit et anonyme : une simple '
              'clé secrète, pas d\'email ni de mot de passe.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cloud_done),
                    label: const Text('Créer un compte'),
                    onPressed: _creerCompte,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.key),
                    label: const Text('J\'ai une clé'),
                    onPressed: _connecterCompte,
                  ),
                ),
              ],
            ),
          ] else ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cloud_done),
              title: Text('Clé : ${m.compteCle.substring(0, 6)}••••••••••••'),
              subtitle: const Text(
                  'Tes modifications sont envoyées automatiquement au compte.'),
              trailing: IconButton(
                tooltip: 'Copier la clé complète',
                icon: const Icon(Icons.copy),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: m.compteCle));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'Clé copiée ✅ Garde-la précieusement (c\'est elle qui donne accès à tes données).')));
                  }
                },
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text('Envoyer'),
                    onPressed: _pousser,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cloud_download),
                    label: const Text('Récupérer'),
                    onPressed: _tirer,
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: _dissocier,
              child: const Text('Dissocier cet appareil'),
            ),
          ],
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
          Text('Mon emploi du temps',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.grid_on),
            title: const Text('Remplir mon emploi du temps'),
            subtitle: const Text(
                'Tableau lundi→samedi : cours, repas, sport… avec semaines A/B'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const EdtScreen())),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_month),
            title: const Text('Calendrier'),
            subtitle: const Text(
                'Roulement semaines A/B, vacances, semaines de révisions'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CalendrierScreen())),
          ),
          const SizedBox(height: 24),
          Text('Concours', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          if (m.dateConcours == null) ...[
            Text(
              'À l\'approche des écrits, active le mode révisions : le plan du '
              'soir bascule sur la rotation de TOUS tes chapitres (jamais revus '
              'd\'abord, puis les plus anciens), avec le compte à rebours J-X.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.flag),
              label: const Text('Fixer la date des écrits'),
              onPressed: _choisirConcours,
            ),
          ] else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.flag),
              title: Text(
                  'Mode révisions actif — écrits le ${frDateCourte(m.dateConcours!)}'),
              subtitle:
                  const Text('Appuie pour changer la date. Le plan du soir fait tourner tes chapitres.'),
              onTap: _choisirConcours,
              trailing: TextButton(
                onPressed: () {
                  m.setDateConcours(null);
                  setState(() {});
                },
                child: const Text('Désactiver'),
              ),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('Tracker d\'annales'),
            subtitle: Text(
                m.annales.isEmpty
                    ? 'Les sujets de concours à faire — le plan du soir pioche dedans à J-45.'
                    : '${m.annales.where((a) => a.fait).length}/${m.annales.length} faites',
                style: const TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AnnalesScreen())),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text('Mode oraux'),
            subtitle: Text(
                m.modeOraux
                    ? 'ACTIF — le plan du soir prépare tes épreuves orales.'
                    : 'Planning des épreuves par concours + bascule du plan du soir.',
                style: const TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const OrauxScreen())),
          ),
          if (!kIsWeb) ...[
            const SizedBox(height: 24),
            Text('Notifications',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Des rappels la VEILLE au soir (19 h), et uniquement ça — pas de spam. (Sur la version web PC, les notifications n\'existent pas.)',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Activer les notifications'),
              value: m.notifsActives,
              onChanged: (v) async {
                if (v) {
                  final ok = await Notifs.demanderPermission();
                  if (!ok) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'Permission refusée — autorise Khompas dans les réglages du téléphone.')));
                    }
                    return;
                  }
                }
                await m.setPrefsNotifs(actives: v);
                await Notifs.replanifier(m);
                if (mounted) setState(() {});
              },
            ),
            if (m.notifsActives) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Veille de khôlle / d\'oral'),
                subtitle: const Text(
                    'Matière, heure, salle et programme si connu.',
                    style: TextStyle(fontSize: 12)),
                value: m.notifVeilleKholle,
                onChanged: (v) async {
                  await m.setPrefsNotifs(veilleKholle: v);
                  await Notifs.replanifier(m);
                  if (mounted) setState(() {});
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Veille de DM / DNS à rendre'),
                subtitle: const Text('Le filet anti-oubli.',
                    style: TextStyle(fontSize: 12)),
                value: m.notifVeilleDm,
                onChanged: (v) async {
                  await m.setPrefsNotifs(veilleDm: v);
                  await Notifs.replanifier(m);
                  if (mounted) setState(() {});
                },
              ),
            ],
          ],
          const SizedBox(height: 24),
          Text('Sommeil', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Fixe une heure limite : le plan du soir se raccourcit tout seul '
            'pour finir avant. Le sommeil consolide la mémoire — travailler '
            'jusqu\'à 1h du matin fait perdre plus qu\'il ne fait gagner.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 8),
          if (m.heureLimiteMin == null)
            OutlinedButton.icon(
              icon: const Icon(Icons.bedtime_outlined),
              label: const Text('Fixer une heure limite'),
              onPressed: _choisirHeureLimite,
            )
          else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bedtime),
              title: Text(
                  'Heure limite : ${m.heureLimiteMin! ~/ 60}h${(m.heureLimiteMin! % 60).toString().padLeft(2, '0')}'),
              subtitle: const Text('Appuie pour changer.'),
              onTap: _choisirHeureLimite,
              trailing: TextButton(
                onPressed: () {
                  m.setHeureLimite(null);
                  setState(() {});
                },
                child: const Text('Retirer'),
              ),
            ),
          if (m.matieres.length >= 2) ...[
            const SizedBox(height: 24),
            Text('Fusionner deux matières',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Un doublon qui résiste (« LV1 » et « Anglais », un khôlleur qui écrit autrement…) ? Tout ce qui est dans la première passera dans la seconde — khôlles, notes, chapitres, heures.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.merge_type),
              label: const Text('Fusionner…'),
              onPressed: _fusionnerDialog,
            ),
          ],
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
            title: Text('Khompas — bêta 0.12'),
            subtitle: Text(
                'Le compagnon de ta prépa. Tes données restent sur ton téléphone.'),
          ),
        ],
      ),
    );
  }
}
