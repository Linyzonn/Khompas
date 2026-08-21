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
      await m.saveCompteCle(cle, nouvelle: true);
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
    // COMPARATIF avant le choix : « ecraser ici ou la » est binaire, mais
    // au moins l'utilisateur voit ce que chaque cote contient.
    String comparatif = '';
    try {
      final (local, distant) = await AppModel.instance.comparerAvecCompte();
      comparatif = '\n\nIci : $local\nSur le compte : $distant';
    } catch (_) {
      // hors ligne ou compte vide : le dialogue reste utilisable sans
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Récupérer du compte ?'),
        content: Text(
            'Les données de cet appareil seront REMPLACÉES par celles du compte '
            '(la dernière version envoyée, depuis n\'importe quel appareil).'
            '$comparatif'),
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

  /// Affiche (et cree au besoin) le lien du flux ICS abonne, pret a copier.
  Future<void> _lienAgenda() async {
    final m = AppModel.instance;
    try {
      final jeton = await ApiKhompas(m.serverUrl).creerJetonIcs(m.compteCle);
      final lien = '${m.serverUrl}/api/compte/ics?j=$jeton';
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ton lien d\'agenda 📅'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(lien, style: const TextStyle(fontSize: 12.5)),
              const SizedBox(height: 10),
              Text(
                'iPhone : Réglages → Calendrier → Comptes → Ajouter → '
                'Abonnement de calendrier.\n'
                'Google Agenda : Autres agendas → + → À partir d\'une URL.\n\n'
                'Le calendrier se met à jour tout seul (quelques heures de '
                'délai selon l\'application). Ce lien est personnel : ne le '
                'partage pas.',
                style: TextStyle(
                    fontSize: 12, color: couleurSecondaire(context)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: lien));
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Copier le lien'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) _snack('Lien impossible : ${_msg(e)}', secondes: 6);
    }
  }

  Future<void> _fusionner() async {
    try {
      final resume = await AppModel.instance.fusionnerAvecCompte();
      if (!mounted) return;
      setState(() {});
      _snack('Fusionné ✅ ($resume)');
    } catch (e) {
      if (mounted) _snack('Fusion impossible : ${_msg(e)}', secondes: 6);
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
      body: listeCentree(context, children: [
          if (m.serverUrl.isEmpty)
            Text(
              'Renseigne d\'abord l\'URL du serveur (Réglages → Données & avancé) pour activer les comptes.',
              style: styleMeta(context),
            )
          else if (m.compteCle.isEmpty) ...[
            Text(
              'Un compte = tes données sauvegardées en ligne et synchronisées '
              'entre ton téléphone et ton PC. Gratuit et anonyme : une simple '
              'clé secrète, pas d\'email ni de mot de passe.',
              style: styleMeta(context),
            ),
            const SizedBox(height: kEsp8),
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
            const SizedBox(height: kEsp8),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.merge),
              label: const Text('Fusionner avec le compte'),
              onPressed: _fusionner,
            ),
            Text(
              'La fusion garde le meilleur des deux côtés : union par '
              'enregistrement, la version la plus récente gagne, les '
              'suppressions sont respectées. « Récupérer » remplace tout.',
              style: styleMeta(context),
            ),
            const SizedBox(height: kEsp16),
            Text('Agenda abonné',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: kEsp4),
            Text(
              'Abonne l\'agenda de ton téléphone à ton lien Khompas : khôlles, '
              'DS, DM et oraux s\'y mettent à jour TOUT SEULS (plus besoin de '
              'ré-exporter quand un programme change).',
              style: styleMeta(context),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              icon: const Icon(Icons.link),
              label: const Text('Mon lien d\'agenda'),
              onPressed: _lienAgenda,
            ),
            TextButton(
              onPressed: _dissocier,
              child: const Text('Dissocier cet appareil'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error),
              onPressed: _supprimerCompte,
              child: const Text('Supprimer mon compte du serveur'),
            ),
          ],
        ],
      ),
    );
  }

  /// RGPD : purge le compte cote SERVEUR (donnees + profil). Les donnees de
  /// cet appareil restent intactes ; seule la copie en ligne disparait.
  Future<void> _supprimerCompte() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ton compte du serveur ?'),
        content: const Text(
            'Toutes les données de ton compte EN LIGNE seront effacées '
            'immédiatement et définitivement du serveur, et ta clé ne '
            'fonctionnera plus.\n\nLes données de CET appareil restent '
            'intactes — tu perds seulement la sauvegarde en ligne et la '
            'synchronisation entre appareils.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await AppModel.instance.supprimerCompteServeur();
      if (mounted) {
        setState(() {});
        _snack('Compte supprimé du serveur ✅ Tes données locales sont intactes.');
      }
    } catch (e) {
      if (mounted) _snack('Suppression impossible : ${_msg(e)}', secondes: 6);
    }
  }
}
