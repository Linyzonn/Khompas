import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';
import '../store.dart';
import 'dialogs.dart';
import 'edt.dart';
import 'import.dart';
import 'import_chapitres.dart';

/// Premier lancement, en DEUX temps :
/// 1. profil (filiere, groupe, 5/2) + compte (anonyme, a cle secrete) ;
/// 2. le FIL DE RENTREE : colloscope -> programme officiel -> emploi du
///    temps — les 10 premieres minutes qui font que l'app sert vraiment.
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
  // 0 = profil/compte, 1 = fil de rentree (3 imports guides).
  int etape = 0;

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
      await montrerCleCompte(context, cle,
          rappel: 'Elle reste visible dans Réglages.');
      if (mounted) setState(() => etape = 1);
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
    final cle = await demanderCleCompte(context);
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
    setState(() => etape = 1);
  }

  Widget _etapeFil(BuildContext context) {
    final m = AppModel.instance;
    final faits = [
      m.colles.isNotEmpty,
      m.chapitres.isNotEmpty,
      m.routines.isNotEmpty,
    ];
    Widget carte(int i, String emoji, String titre, String sous,
        Widget Function() destination) {
      return Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: faits[i]
                  ? Colors.green.withValues(alpha: 0.6)
                  : Colors.grey.withValues(alpha: 0.3)),
        ),
        child: ListTile(
          leading: Text(faits[i] ? '✅' : emoji,
              style: const TextStyle(fontSize: 24)),
          title: Text('${i + 1}. $titre',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(sous, style: const TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await Navigator.push(
                context, MaterialPageRoute(builder: (_) => destination()));
            if (mounted) setState(() {});
          },
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 16),
        const Center(child: Text('🧭', style: TextStyle(fontSize: 44))),
        const SizedBox(height: 8),
        Center(
          child: Text('Trois étapes et tout roule',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 20),
            child: Text(
              'Chaque étape se saute et se refait plus tard — mais avec les trois, le plan du soir devient vraiment intelligent.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),
        ),
        carte(0, '📸', 'Mon colloscope',
            'Une photo ou le code de ta classe — toutes tes khôlles avec salle et heure.',
            () => const ImportScreen()),
        carte(1, '📖', 'Le programme officiel',
            'Tous les chapitres de ta filière pré-remplis (gratuit, par IA).',
            () => const ImportChapitresScreen()),
        carte(2, '🗓️', 'Mon emploi du temps',
            '5 minutes sur la grille — le plan du soir saura ce que tu as vu chaque jour.',
            () => const EdtScreen()),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => AppModel.instance.setOnboarded(),
          child: const Text('C\'est parti !'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final serveurActif = AppModel.instance.serverUrl.isNotEmpty;
    if (etape == 1) {
      return Scaffold(body: SafeArea(child: _etapeFil(context)));
    }
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
              initialValue: filiere,
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
                child: const Text(
                  kIsWeb
                      ? 'Continuer sans compte (⚠ déconseillé sur navigateur : un nettoyage des données du navigateur efface tout)'
                      : 'Continuer sans compte (local seulement)',
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
