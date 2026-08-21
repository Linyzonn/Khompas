import 'package:flutter/material.dart';

import '../../store.dart';
import '../../theme.dart';
import '../calendrier.dart';
import '../edt.dart';

/// Sous-page Reglages : emploi du temps, calendrier interne, priorites de
/// matieres et fusion de doublons.
class PlanningPage extends StatefulWidget {
  const PlanningPage({super.key});

  @override
  State<PlanningPage> createState() => _PlanningPageState();
}

class _PlanningPageState extends State<PlanningPage> {
  void _snack(String msg, {int secondes = 4}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: Duration(seconds: secondes),
      content: Text(msg),
    ));
  }

  Future<void> _trajetPersonnalise() async {
    final m = AppModel.instance;
    final ctl = TextEditingController(
        text: m.trajetMinutes == 0 ? '' : m.trajetMinutes.toString());
    final minutes = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Temps de trajet quotidien'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              labelText: 'Minutes (aller simple)',
              helperText: 'Entre 5 et 180 minutes.'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(context, int.tryParse(ctl.text.trim())),
              child: const Text('OK')),
        ],
      ),
    );
    if (minutes == null || minutes < 5) return;
    m.setTrajetMinutes(minutes);
    if (mounted) setState(() {});
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

  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Planning & matières')),
      body: listeCentree(context, children: [
          Text('Mon emploi du temps',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: kEsp4),
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
                    MaterialPageRoute(builder: (_) => const CalendrierScreen()))
                .then((_) => setState(() {})),
          ),
          // Raccourci DIRECT : l'import des vacances officielles etait
          // enterre dans le Calendrier — personne ne le trouvait.
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Text('🏖', style: TextStyle(fontSize: 20)),
            title: const Text('Vacances officielles (zone A / B / C)'),
            subtitle: Text(
                m.zoneVacances.isEmpty
                    ? 'Choisis ta zone → toutes les vacances de l\'année arrivent d\'un coup.'
                    : 'Zone ${m.zoneVacances} · ${m.sansCours.length} période(s) au calendrier — appuie pour mettre à jour.',
                style: const TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        const CalendrierScreen(ouvrirVacances: true))).then(
                (_) => setState(() {})),
          ),
          const SizedBox(height: kEsp24),
          Text('Temps de trajet',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: kEsp4),
          Text(
            'Métro, bus, RER ? Le tableau de bord te proposera tes cartes '
            '(voc d\'anglais, citations de français) à réviser pendant le '
            'trajet — le travail utile qui ne demande ni table ni papier.',
            style: styleMeta(context),
          ),
          const SizedBox(height: kEsp8),
          Wrap(
            spacing: 6,
            children: [
              for (final (minutes, label) in const [
                (0, 'Pas de trajet'),
                (15, '15 min'),
                (30, '30 min'),
                (45, '45 min'),
                (60, '1 h'),
              ])
                ChoiceChip(
                  label: Text(label, style: const TextStyle(fontSize: 12)),
                  selected: m.trajetMinutes == minutes,
                  onSelected: (_) {
                    m.setTrajetMinutes(minutes);
                    setState(() {});
                  },
                ),
              // Duree personnalisee (« Autre… ») : tout le monde n'a pas
              // un trajet rond.
              ChoiceChip(
                label: Text(
                    const [0, 15, 30, 45, 60].contains(m.trajetMinutes)
                        ? 'Autre…'
                        : '${m.trajetMinutes} min',
                    style: const TextStyle(fontSize: 12)),
                selected:
                    !const [0, 15, 30, 45, 60].contains(m.trajetMinutes),
                onSelected: (_) => _trajetPersonnalise(),
              ),
            ],
          ),
          const SizedBox(height: kEsp24),
          Text('Priorité des matières',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: kEsp4),
          Text(
            'Pondère le plan de travail (coefficients aux concours, matière à rattraper…).',
            style: styleMeta(context),
          ),
          const SizedBox(height: kEsp8),
          if (m.matieres.isEmpty)
            Text('Les matières apparaîtront après ton premier import.',
                style: TextStyle(color: couleurSecondaire(context))),
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
                        label: Text('★' * p),
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
          if (m.matieres.length >= 2) ...[
            const SizedBox(height: kEsp24),
            Text('Fusionner deux matières',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: kEsp4),
            Text(
              'Un doublon qui résiste (« LV1 » et « Anglais », un khôlleur qui écrit autrement…) ? Tout ce qui est dans la première passera dans la seconde — khôlles, notes, chapitres, heures.',
              style: styleMeta(context),
            ),
            const SizedBox(height: kEsp8),
            OutlinedButton.icon(
              icon: const Icon(Icons.merge_type),
              label: const Text('Fusionner…'),
              onPressed: _fusionnerDialog,
            ),
          ],
        ],
      ),
    );
  }
}
