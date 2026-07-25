import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_client.dart';
import '../models.dart';
import '../store.dart';

/// Premier lancement : profil (filiere, groupe, 5/2) + creation ou
/// connexion du compte (anonyme, a cle secrete). On peut aussi tout sauter.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  String filiere = 'PCSI';
  final groupeCtl = TextEditingController(text: '1');
  bool cinqDemi = false;
  bool busy = false;

  void _snack(String msg, {int secondes = 5}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: Duration(seconds: secondes),
      content: Text(msg),
    ));
  }

  void _profilLocal() {
    final m = AppModel.instance;
    m.setProfil(
        filiere: filiere, groupe: int.tryParse(groupeCtl.text.trim()) ?? 1);
    m.setCinqDemi(cinqDemi);
  }

  Future<void> _creerCompte() async {
    final m = AppModel.instance;
    setState(() => busy = true);
    try {
      _profilLocal();
      final cle = await ApiKhompas(m.serverUrl)
          .creerCompte(filiere: filiere, cinqDemi: cinqDemi);
      await m.saveCompteCle(cle);
      try {
        await m.pousserCompte();
      } catch (_) {
        // le push automatique reessaiera a la prochaine modification
      }
      if (!mounted) return;
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
                'NOTE-LA précieusement (notes du téléphone, mail à toi-même…) : '
                'c\'est elle — et elle seule — qui permet de retrouver tes '
                'données sur un autre appareil ou après une réinstallation. '
                'Elle reste visible dans Réglages.',
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
              child: const Text('C\'est noté'),
            ),
          ],
        ),
      );
      await m.setOnboarded();
    } catch (e) {
      if (mounted) {
        _snack(
            'Impossible de créer le compte (${e.toString().replaceFirst('Exception: ', '')}). Tu peux continuer sans compte et réessayer depuis Réglages.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _dejaUneCle() async {
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
            border: OutlineInputBorder(),
            hintText: '18 caractères',
          ),
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
    setState(() => busy = true);
    try {
      final resume = await m.connecterCompte(cle);
      if (!mounted) return;
      _snack('Compte connecté ✅ ($resume)');
      await m.setOnboarded();
    } catch (e) {
      if (mounted) {
        _snack(
            'Connexion impossible : ${e.toString().replaceFirst('Exception: ', '')}');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _sansCompte() async {
    _profilLocal();
    await AppModel.instance.setOnboarded();
  }

  @override
  Widget build(BuildContext context) {
    final serveurActif = AppModel.instance.serverUrl.isNotEmpty;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            const Center(child: Text('🧭', style: TextStyle(fontSize: 56))),
            const SizedBox(height: 8),
            Center(
              child: Text('Khompas',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold)),
            ),
            Center(
              child: Text('Le compagnon de ta prépa',
                  style: TextStyle(color: Colors.grey.shade600)),
            ),
            const SizedBox(height: 28),
            DropdownButtonFormField<String>(
              value: filiere,
              decoration: const InputDecoration(
                  labelText: 'Ma filière', border: OutlineInputBorder()),
              items: [
                for (final f in kFilieres)
                  DropdownMenuItem(value: f, child: Text(f)),
              ],
              onChanged: (v) => setState(() => filiere = v ?? filiere),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: groupeCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Mon groupe de colle (modifiable plus tard)',
                border: OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Je suis 5/2'),
              subtitle: const Text(
                  'Je refais ma 2e année — Khompas s\'adapte (programme déjà vu).'),
              value: cinqDemi,
              onChanged: (v) => setState(() => cinqDemi = v),
            ),
            const SizedBox(height: 16),
            if (busy) const Center(child: CircularProgressIndicator()),
            if (!busy && serveurActif) ...[
              FilledButton.icon(
                icon: const Icon(Icons.cloud_done),
                label: const Text('Créer mon compte'),
                onPressed: _creerCompte,
              ),
              const SizedBox(height: 4),
              Text(
                'Gratuit et anonyme : une simple clé secrète. Tes données sont '
                'sauvegardées en ligne et synchronisées entre ton téléphone et ton PC.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.key),
                label: const Text('J\'ai déjà une clé de compte'),
                onPressed: _dejaUneCle,
              ),
              const SizedBox(height: 8),
            ],
            if (!busy)
              TextButton(
                onPressed: _sansCompte,
                child: const Text('Continuer sans compte (local seulement)'),
              ),
          ],
        ),
      ),
    );
  }
}
