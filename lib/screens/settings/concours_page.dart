import 'package:flutter/material.dart';

import '../../models.dart';
import '../../store.dart';
import '../../theme.dart';
import '../annales.dart';
import '../cartes.dart';
import '../lectures.dart';
import '../oraux.dart';

/// Sous-page Reglages : mode revisions concours (date des ecrits), annales,
/// oeuvres de francais, jalons TIPE/SCEI et mode oraux.
class ConcoursPage extends StatefulWidget {
  const ConcoursPage({super.key});

  @override
  State<ConcoursPage> createState() => _ConcoursPageState();
}

class _ConcoursPageState extends State<ConcoursPage> {
  void _snack(String msg, {int secondes = 4}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: Duration(seconds: secondes),
      content: Text(msg),
    ));
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

  // ---------- Jalons TIPE / SCEI (version "a confirmer" : les dates
  // exactes changent chaque annee — on PROPOSE, l'utilisateur ajuste) ----------

  Future<void> _jalonsTipeDialog() async {
    final m = AppModel.instance;
    final now = DateTime.now();
    // Annee scolaire en cours : SCEI en decembre, MCOT en fevrier suivant.
    final anneeScei = now.month >= 8 ? now.year : now.year - 1;
    var dateScei = DateTime(anneeScei, 12, 10);
    var dateMcot = DateTime(anneeScei + 1, 2, 10);
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          title: const Text('Jalons TIPE / SCEI'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dates PROPOSÉES d\'après les années précédentes — vérifie-les sur scei-concours.fr et ajuste avant d\'ajouter.',
                style: TextStyle(fontSize: 12.5, color: couleurSecondaire(context)),
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Clôture inscriptions SCEI'),
                trailing: OutlinedButton(
                  child: Text(frDateCourte(dateScei)),
                  onPressed: () async {
                    final d = await showDatePicker(
                        context: context,
                        initialDate: dateScei,
                        firstDate: DateTime(now.year - 1),
                        lastDate: DateTime(now.year + 2));
                    if (d != null) setDlg(() => dateScei = d);
                  },
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Dépôt du MCOT'),
                trailing: OutlinedButton(
                  child: Text(frDateCourte(dateMcot)),
                  onPressed: () async {
                    final d = await showDatePicker(
                        context: context,
                        initialDate: dateMcot,
                        firstDate: DateTime(now.year - 1),
                        lastDate: DateTime(now.year + 2));
                    if (d != null) setDlg(() => dateMcot = d);
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                m.addEvenement(Evenement(
                    titre: '🚨 Clôture inscriptions SCEI (vérifie l\'heure !)',
                    matiere: 'TIPE',
                    date: dateScei,
                    debutMin: 8 * 60,
                    dureeMin: 60));
                m.addEvenement(Evenement(
                    titre: '🚨 Dépôt du MCOT (TIPE)',
                    matiere: 'TIPE',
                    date: dateMcot,
                    debutMin: 8 * 60,
                    dureeMin: 60));
                Navigator.pop(context);
                _snack(
                    'Jalons ajoutés à l\'agenda ✅ (notification la veille si les notifs sont actives)');
              },
              child: const Text('Ajouter les 2 jalons'),
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
      appBar: AppBar(title: const Text('Concours & oraux')),
      body: listeCentree(context, children: [
          Text('Concours', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: kEsp4),
          if (m.dateConcours == null) ...[
            Text(
              'À l\'approche des écrits, active le mode révisions : le plan du '
              'soir bascule sur la rotation de TOUS tes chapitres (jamais revus '
              'd\'abord, puis les plus anciens), avec le compte à rebours J-X.',
              style: styleMeta(context),
            ),
            const SizedBox(height: kEsp8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.flag),
                    label: const Text('Fixer la date des écrits'),
                    onPressed: _choisirConcours,
                  ),
                ),
                // Filiere de 2e annee : la date approximative est connue
                // d'avance (les ecrits demarrent ~ 20 avril) — un tap
                // suffit, ajustable ensuite.
                if (kFilieresDeuxiemeAnnee.contains(m.filiere)) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('≈ 20 avril'),
                      onPressed: () {
                        final now = DateTime.now();
                        final annee =
                            now.month >= 8 ? now.year + 1 : now.year;
                        m.setDateConcours(DateTime(annee, 4, 20));
                        setState(() {});
                        _snack(
                            'Écrits pré-remplis au 20 avril $annee — ajuste la date exacte quand elle sera connue.');
                      },
                    ),
                  ),
                ],
              ],
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
            leading: const Text('📖', style: TextStyle(fontSize: 20)),
            title: const Text('Œuvres de français'),
            subtitle: Text(
                m.oeuvres.isEmpty
                    ? 'Les 3 livres de l\'année — à lire pendant l\'été, le plan s\'en charge.'
                    : '${m.oeuvres.where((o) => o.finie).length}/${m.oeuvres.length} lues',
                style: const TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const LecturesScreen())),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Text('📜', style: TextStyle(fontSize: 20)),
            title: const Text('Citations de français'),
            subtitle: Text(
                m.citations.isEmpty
                    ? 'Par axe du thème, avec « comment s\'en servir » — révisées façon Anki.'
                    : '${m.citations.length} citation(s) · ${m.citationsDues().length} à revoir',
                style: const TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const CitationsScreen()))
                .then((_) => setState(() {})),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Text('🇬🇧', style: TextStyle(fontSize: 20)),
            title: const Text('Voc d\'anglais'),
            subtitle: Text(
                m.vocab.isEmpty
                    ? 'Le voc exigé en khôlle — révisé façon Anki (français → anglais).'
                    : '${m.vocab.length} mot(s) · ${m.vocabDus().length} à revoir',
                style: const TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const VocabScreen()))
                .then((_) => setState(() {})),
          ),
          if (kFilieresDeuxiemeAnnee.contains(m.filiere))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Text('🧪', style: TextStyle(fontSize: 20)),
              title: const Text('Jalons TIPE / SCEI'),
              subtitle: const Text(
                  'Inscriptions concours (décembre) et MCOT (février) — les dates couperets que des candidats ratent chaque année.',
                  style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _jalonsTipeDialog,
            ),
          const SizedBox(height: kEsp16),
          Text('EPL/S — pilote de ligne (ENAC)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: kEsp4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Je prépare l’EPL/S'),
            subtitle: const Text(
                'Concours à part : 3 QCM de 2 h coeff 1 — maths sur le programme de PCSI, physique sur celui de MPSI, anglais (éliminatoire sous 8) — puis sélections psychotechniques PSY 1 et PSY 2. Le plan du soir ajoute un bloc d’entraînement quotidien en rotation.',
                style: TextStyle(fontSize: 12)),
            value: m.eplS,
            onChanged: (v) {
              m.setEplS(v, date: m.dateEplS);
              setState(() {});
            },
          ),
          if (m.eplS)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.flight_takeoff),
              title: Text(m.dateEplS == null
                  ? 'Fixer la date des écrits EPL/S'
                  : 'Écrits EPL/S le ${frDateCourte(m.dateEplS!)}'),
              subtitle: const Text(
                  'Avec la date : compte à rebours, et les séries s’allongent sur le dernier mois. Les tests psy se gagnent à l’habitude — ne les découvre pas le jour J.',
                  style: TextStyle(fontSize: 12)),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: m.dateEplS ??
                      DateTime.now().add(const Duration(days: 120)),
                  firstDate: DateTime(2023),
                  lastDate: DateTime(2032),
                );
                if (d != null) {
                  m.setEplS(true, date: d);
                  setState(() {});
                }
              },
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
        ],
      ),
    );
  }
}
