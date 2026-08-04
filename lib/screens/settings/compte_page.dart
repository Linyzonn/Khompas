import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api_client.dart';
import '../../store.dart';
import '../../theme.dart';
import '../dialogs.dart';

/// Sous-page Reglages : compte anonyme (cle secrete) et synchronisation
/// telephone <-> PC.
class ComptePage extends StatefulWidget {
  const ComptePage({super.key});

  @override
  State<ComptePage> createState() => _ComptePageState();
}

class _ComptePageState extends State<ComptePage> {
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
      await montrerCleCompte(context, cle,
          rappel: 'Elle reste visible ici (icône copier).');
    } catch (e) {
      if (mounted) _snack('Création impossible : ${_msg(e)}', secondes: 6);
    }
  }

  Future<void> _connecterCompte() async {
    final m = AppModel.instance;
    final cle = await demanderCleCompte(context);
    if (cle == null || cle.trim().isEmpty || !mounted) return;
    try {
      final resume = await m.connecterCompte(cle);
      if (!mounted) return;
      setState(() {});
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
      setState(() {});
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

  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Compte & synchronisation')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (m.serverUrl.isEmpty)
            Text(
              'Renseigne d\'abord l\'URL du serveur (Réglages → Données & avancé) pour activer les comptes.',
              style: TextStyle(color: couleurSecondaire(context), fontSize: 12),
            )
          else if (m.compteCle.isEmpty) ...[
            Text(
              'Un compte = tes données sauvegardées en ligne et synchronisées '
              'entre ton téléphone et ton PC. Gratuit et anonyme : une simple '
              'clé secrète, pas d\'email ni de mot de passe.',
              style: TextStyle(color: couleurSecondaire(context), fontSize: 12),
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
        ],
      ),
    );
  }
}
