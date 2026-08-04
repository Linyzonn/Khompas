import 'package:flutter/material.dart';

import '../../models.dart';
import '../../store.dart';
import '../../theme.dart';
import '../bilan_concours.dart';
import '../dialogs.dart';

/// Sous-page Reglages : profil (filiere, groupe, 5/2) et transitions de
/// scolarite (passage en 2e annee, devenir 5/2, outils de la 5/2).
class ProfilPage extends StatefulWidget {
  const ProfilPage({super.key});

  @override
  State<ProfilPage> createState() => _ProfilPageState();
}

class _ProfilPageState extends State<ProfilPage> {
  late final TextEditingController groupeCtl;

  @override
  void initState() {
    super.initState();
    groupeCtl =
        TextEditingController(text: AppModel.instance.groupe.toString());
  }

  @override
  void dispose() {
    groupeCtl.dispose();
    super.dispose();
  }

  void _snack(String msg, {int secondes = 4}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: Duration(seconds: secondes),
      content: Text(msg),
    ));
  }

  // ---------- Passage en 2e annee (l'ecran de septembre) ----------

  Future<void> _passageDeuxiemeAnnee() async {
    final m = AppModel.instance;
    // Les VRAIS choix de filiere de 2e annee : un PCSI part en PC ou en
    // PSI (avant, PSI etait impose en silence), un MPSI en MP ou PSI...
    final suggestions = switch (m.filiere) {
      'MPSI' => ['MP', 'PSI'],
      'PCSI' => ['PC', 'PSI'],
      'PTSI' => ['PT', 'PSI'],
      'MP2I' => ['MPI', 'MP'],
      _ => ['PSI'],
    };
    var nouvelleFiliere = suggestions.first;
    var nettoyer = true;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          title: const Text('Passage en 2e année 🎓'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (suggestions.length > 1) ...[
                Text('Depuis ${m.filiere}, tu peux partir en :',
                    style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final f in suggestions)
                      ChoiceChip(
                        label: Text(f),
                        selected: nouvelleFiliere == f,
                        onSelected: (_) =>
                            setDlg(() => nouvelleFiliere = f),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              DropdownButtonFormField<String>(
                key: ValueKey(nouvelleFiliere),
                initialValue: nouvelleFiliere,
                decoration: const InputDecoration(
                    labelText: 'Nouvelle filière',
                    border: OutlineInputBorder()),
                items: [
                  for (final f in kFilieres)
                    DropdownMenuItem(value: f, child: Text(f)),
                ],
                onChanged: (v) =>
                    setDlg(() => nouvelleFiliere = v ?? nouvelleFiliere),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Supprimer les khôlles passées',
                    style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                    'Notes, chapitres et heures de travail sont CONSERVÉS.',
                    style: TextStyle(fontSize: 11.5)),
                value: nettoyer,
                onChanged: (v) => setDlg(() => nettoyer = v ?? true),
              ),
              Text(
                'Ensuite : importe le colloscope de ta nouvelle classe et le programme de ta nouvelle filière (le dédoublonnage protège des ré-imports).',
                style: TextStyle(fontSize: 12, color: couleurSecondaire(context)),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                m.setProfil(filiere: nouvelleFiliere, groupe: m.groupe);
                if (nettoyer) m.nettoyerCollesPassees();
                Navigator.pop(context);
                _snack(
                    'Bienvenue en $nouvelleFiliere 🎓 Pense au nouveau colloscope (Agenda → import).');
              },
              child: const Text('C\'est parti'),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// Devenir 5/2 : on GARDE la filiere et tout l'historique (chapitres,
  /// notes, erreurs — c'est le capital de l'annee passee), on active le
  /// mode 5/2, et on propose le menage des kholles passees. Les deux
  /// prochaines etapes (bilan de concours, reactivation d'ete) sont
  /// pointees explicitement.
  Future<void> _devenirCinqDemi() async {
    final m = AppModel.instance;
    var nettoyer = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          title: const Text('Je refais ma 2e année 💪'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tout ton historique est conservé : chapitres, notes, cahier '
                'd\'erreurs — c\'est ton capital pour cette année.',
                style: TextStyle(fontSize: 13),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Supprimer les khôlles passées',
                    style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                    'Le nouveau colloscope arrivera à la rentrée.',
                    style: TextStyle(fontSize: 11.5)),
                value: nettoyer,
                onChanged: (v) => setDlg(() => nettoyer = v ?? true),
              ),
              Text(
                'Ensuite, deux réflexes de 5/2 :\n'
                '1. 🎯 Bilan de concours — saisis tes notes de l\'an dernier '
                'pour cibler où tu perds des points ;\n'
                '2. ☀️ Réactivation d\'été — étale la révision du programme '
                'sur les vacances.',
                style: TextStyle(fontSize: 12, color: couleurSecondaire(context)),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('C\'est parti')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    m.setCinqDemi(true);
    if (nettoyer) m.nettoyerCollesPassees();
    if (!mounted) return;
    setState(() {});
    _snack(
        'Mode 5/2 activé 💪 La section « Ma 5/2 » est apparue juste en dessous du profil.');
  }

  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Profil & scolarité')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Mon profil', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: kFilieres.contains(m.filiere) ? m.filiere : 'Autre',
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
                'Je refais ma 2e année — chapitres importés « déjà vus », bilan de concours, et réactivation d\'été.'),
            value: m.cinqDemi,
            onChanged: (v) {
              m.setCinqDemi(v);
              setState(() {});
            },
          ),
          if (!kFilieresDeuxiemeAnnee.contains(m.filiere))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Text('🎓', style: TextStyle(fontSize: 20)),
              title: const Text('Je passe en 2e année'),
              subtitle: const Text(
                  'Nouvelle filière, ménage des khôlles passées, prêt pour le nouveau colloscope.',
                  style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _passageDeuxiemeAnnee,
            ),
          if (kFilieresDeuxiemeAnnee.contains(m.filiere) && !m.cinqDemi)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Text('💪', style: TextStyle(fontSize: 20)),
              title: const Text('Je refais ma 2e année (5/2)'),
              subtitle: const Text(
                  'Garde ta filière, active le mode 5/2 : bilan de concours, réactivation d\'été, ménage des khôlles passées.',
                  style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _devenirCinqDemi,
            ),
          if (m.cinqDemi) ...[
            const SizedBox(height: 24),
            Text('Ma 5/2', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Text('🎯', style: TextStyle(fontSize: 20)),
              title: const Text('Bilan de concours'),
              subtitle: const Text(
                  'Tes notes de l\'an dernier par épreuve → où tu perds des points → priorités de matières.',
                  style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BilanConcoursScreen()),
              ).then((_) => setState(() {})),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Text('☀️', style: TextStyle(fontSize: 20)),
              title: const Text('Planifier ma réactivation d\'été'),
              subtitle: const Text(
                  'Répartit la révision de tous tes chapitres sur les jours restants des grandes vacances (matières prioritaires d\'abord).',
                  style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await planifierReactivationEte(context);
                if (mounted) setState(() {});
              },
            ),
          ],
        ],
      ),
    );
  }
}
