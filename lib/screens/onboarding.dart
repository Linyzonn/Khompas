import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import 'bilan_concours.dart';
import 'dialogs.dart';
import 'edt.dart';
import 'import.dart';
import 'import_chapitres.dart';
import 'lectures.dart';

/// Premier lancement, en DEUX temps :
/// 1. profil (filiere, groupe, 5/2) + compte (anonyme, a cle secrete) ;
/// 2. selon la saison :
///    - hors ete, le FIL DE RENTREE : colloscope -> programme officiel ->
///      emploi du temps — les 10 premieres minutes qui font que l'app sert ;
///    - en ETE (juillet/aout), un parcours adapte : une 5/2 est guidee vers
///      programme « deja vu » -> bilan de concours -> reactivation d'ete ->
///      oeuvres (le theme change chaque annee) -> devoirs de rentree ;
///      un sup vers programme + oeuvres + devoirs de vacances. Le fil de
///      rentree reste accessible en un tap (« le preparer quand meme »).
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
  // 0 = profil/compte, 1 = parcours guide (rentree ou ete).
  int etape = 0;
  // En ete, l'utilisateur peut basculer vers le fil de rentree classique.
  bool montrerFilRentree = false;
  // La reactivation d'ete n'est pas detectable dans les donnees : on
  // memorise le succes le temps de l'onboarding.
  bool reactivationFaite = false;

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
      await m.saveCompteCle(cle, nouvelle: true);
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

  /// Carte d'etape guidee (✅ + bordure verte quand c'est fait). [action]
  /// pousse un ecran OU ouvre un dialogue — le retour re-evalue l'etat.
  Widget _carte({
    required int numero,
    required String emoji,
    required String titre,
    required String sousTitre,
    required bool fait,
    required Future<void> Function() action,
  }) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: fait
                ? Colors.green.withValues(alpha: 0.6)
                : Colors.grey.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        leading:
            Text(fait ? '✅' : emoji, style: const TextStyle(fontSize: 24)),
        title: Text('$numero. $titre',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(sousTitre, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await action();
          if (mounted) setState(() {});
        },
      ),
    );
  }

  Future<void> _ouvrir(Widget Function() destination) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => destination()));

  /// En ete, l'etalement des DM (creneaux a cadence visible) et la
  /// reactivation s'appuient sur une plage de vacances dans le calendrier —
  /// qu'un tout nouvel utilisateur n'a pas encore. On la cree au moment ou
  /// elle devient utile (premier devoir note), en l'annoncant.
  void _assurerPlageEte() {
    final m = AppModel.instance;
    final now = DateTime.now();
    if (!m.estEte() || m.plageSansCours(now) != null) return;
    m.addPlageSansCours(PlageSansCours(
      titre: 'Grandes vacances',
      debut: DateTime(now.year, now.month, now.day),
      fin: DateTime(now.month >= 9 ? now.year + 1 : now.year, 8, 31),
      type: 'ete',
    ));
    _snack(
        'Plage « Grandes vacances » créée jusqu\'au 31 août — le plan sait maintenant que tu es en vacances (modifiable dans Réglages → Planning).');
  }

  /// En-tete commun de l'etape 1 (emoji + titre + phrase de contexte).
  List<Widget> _entete(BuildContext context, String emoji, String titre,
      String sousTitre) {
    return [
      const SizedBox(height: 16),
      Center(child: Text(emoji, style: const TextStyle(fontSize: 44))),
      const SizedBox(height: 8),
      Center(
        child: Text(titre,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
      ),
      Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 20),
          child: Text(
            sousTitre,
            textAlign: TextAlign.center,
            style: TextStyle(color: couleurSecondaire(context), fontSize: 13),
          ),
        ),
      ),
    ];
  }

  Widget _etapeFil(BuildContext context) {
    final m = AppModel.instance;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        ..._entete(context, '🧭', 'Trois étapes et tout roule',
            'Chaque étape se saute et se refait plus tard — mais avec les trois, le plan du soir devient vraiment intelligent.'),
        _carte(
            numero: 1,
            emoji: '📸',
            titre: 'Mon colloscope',
            sousTitre:
                'Une photo ou le code de ta classe — toutes tes khôlles avec salle et heure.',
            fait: m.colles.isNotEmpty,
            action: () => _ouvrir(() => const ImportScreen())),
        _carte(
            numero: 2,
            emoji: '📖',
            titre: 'Le programme officiel',
            sousTitre:
                'Tous les chapitres de ta filière pré-remplis (gratuit, par IA).',
            fait: m.chapitres.isNotEmpty,
            action: () => _ouvrir(() => const ImportChapitresScreen())),
        _carte(
            numero: 3,
            emoji: '🗓️',
            titre: 'Mon emploi du temps',
            sousTitre:
                '5 minutes sur la grille — le plan du soir saura ce que tu as vu chaque jour.',
            fait: m.routines.isNotEmpty,
            action: () => _ouvrir(() => const EdtScreen())),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => AppModel.instance.setOnboarded(),
          child: const Text('C\'est parti !'),
        ),
      ],
    );
  }

  /// Parcours d'ETE d'une 5/2 : le programme (deja vu) d'abord — la
  /// reactivation ne planifie que des chapitres importes.
  Widget _etapeEte52(BuildContext context) {
    final m = AppModel.instance;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        ..._entete(context, '☀️', 'Ton été de 5/2',
            'L\'été d\'une 5/2 se joue maintenant : trois étapes pour transformer les vacances en tremplin.'),
        _carte(
            numero: 1,
            emoji: '📖',
            titre: 'Le programme officiel',
            sousTitre:
                'Tous les chapitres de ta filière, marqués « déjà vus » (tu es 5/2).',
            fait: m.chapitres.isNotEmpty,
            action: () => _ouvrir(() => const ImportChapitresScreen())),
        _carte(
            numero: 2,
            emoji: '🎯',
            titre: 'Bilan de concours',
            sousTitre:
                'Tes notes de l\'an dernier, épreuve par épreuve → où tu perds des points.',
            fait: m.resultatsConcours.isNotEmpty,
            action: () => _ouvrir(() => const BilanConcoursScreen())),
        _carte(
            numero: 3,
            emoji: '🌊',
            titre: 'Réactivation d\'été',
            sousTitre:
                'Répartit la révision de tes chapitres sur les jours de vacances restants.',
            fait: reactivationFaite,
            action: () async {
              final n = await planifierReactivationEte(context);
              if (n != null && n > 0) reactivationFaite = true;
            }),
        _carte(
            numero: 4,
            emoji: '📚',
            titre: 'Les œuvres de français',
            sousTitre:
                'Le NOUVEAU thème et ses 3 livres — le programme change chaque année, l\'été est LE moment pour les lire.',
            fait: m.oeuvres.isNotEmpty,
            action: () => _ouvrir(() => const LecturesScreen())),
        _carte(
            numero: 5,
            emoji: '📥',
            titre: 'Mes devoirs de rentrée',
            sousTitre: m.devoirs.isEmpty
                ? 'Les DM donnés pour septembre — le plan te les glissera dans tes journées à l\'approche de la rentrée.'
                : '${m.devoirs.length} noté(s) — appuie pour en ajouter un autre.',
            fait: m.devoirs.isNotEmpty,
            action: () async {
              final d = await editDevoirDialog(context);
              if (d != null) {
                AppModel.instance.addDevoir(d);
                _assurerPlageEte();
              }
            }),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => AppModel.instance.setOnboarded(),
          child: const Text('C\'est parti !'),
        ),
        TextButton(
          onPressed: () => setState(() => montrerFilRentree = true),
          child: const Text(
            'Le fil de rentrée (colloscope, emploi du temps) t\'attendra en septembre — le préparer quand même',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  /// Parcours d'ETE d'un sup / d'une spé qui decouvre l'app en vacances :
  /// deux choses utiles tout de suite, le reste attendra la rentree.
  Widget _etapeEteSup(BuildContext context) {
    final m = AppModel.instance;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        ..._entete(context, '☀️', 'Bien commencer, dès les vacances',
            'Deux choses utiles avant même la rentrée — le reste attendra septembre.'),
        _carte(
            numero: 1,
            emoji: '📖',
            titre: 'Le programme officiel',
            sousTitre:
                'Tous les chapitres de ta filière pré-remplis (gratuit, par IA).',
            fait: m.chapitres.isNotEmpty,
            action: () => _ouvrir(() => const ImportChapitresScreen())),
        _carte(
            numero: 2,
            emoji: '📚',
            titre: 'Les œuvres de français',
            sousTitre:
                'Le thème et ses 3 livres — l\'été est LE moment pour les lire, le plan s\'en charge.',
            fait: m.oeuvres.isNotEmpty,
            action: () => _ouvrir(() => const LecturesScreen())),
        _carte(
            numero: 3,
            emoji: '📥',
            titre: 'Mes devoirs de rentrée',
            sousTitre: m.devoirs.isEmpty
                ? 'Ta prépa t\'a donné un devoir de vacances ? Note-le : le plan l\'étale sur l\'été.'
                : '${m.devoirs.length} noté(s) — appuie pour en ajouter un autre.',
            fait: m.devoirs.isNotEmpty,
            action: () async {
              final d = await editDevoirDialog(context);
              if (d != null) {
                AppModel.instance.addDevoir(d);
                _assurerPlageEte();
              }
            }),
        const SizedBox(height: 8),
        Text(
          'Le fil de rentrée (colloscope, emploi du temps) t\'attendra en septembre — tu le retrouveras sur le tableau de bord.',
          textAlign: TextAlign.center,
          style: TextStyle(color: couleurSecondaire(context), fontSize: 12.5),
        ),
        TextButton(
          onPressed: () => setState(() => montrerFilRentree = true),
          child: const Text('Le préparer quand même'),
        ),
        const SizedBox(height: 8),
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
      // Le MODELE fait foi (pas la variable locale) : « J'ai déjà une clé »
      // ou une restauration peuvent avoir change cinqDemi entre-temps.
      final m = AppModel.instance;
      final ete = m.estEte() && !montrerFilRentree;
      final corps = !ete
          ? _etapeFil(context)
          : m.cinqDemi
              ? _etapeEte52(context)
              : _etapeEteSup(context);
      return Scaffold(body: SafeArea(child: corps));
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
                  style: TextStyle(color: couleurSecondaire(context))),
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
                style: TextStyle(color: couleurSecondaire(context), fontSize: 12),
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
