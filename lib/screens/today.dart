import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine.dart';
import '../models.dart';
import '../store.dart';
import 'dialogs.dart';
import 'erreurs.dart';
import 'minuteur.dart';
import 'oraux.dart';
import 'semaine.dart';
import 'settings.dart';

/// Onglet "Aujourd'hui" — le COCKPIT :
/// - grand ecran : blocs a gauche (kholle, a rendre, semaine), LA SESSION DU
///   SOIR au centre (le plus important), blocs a droite (concours, journee,
///   heures) ;
/// - telephone : session du soir d'abord, blocs ensuite.
/// Cartes nettes a barre d'accent coloree (pas de fonds delaves).
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  int minutes = 120;

  // Une proposition de recap par JOUR (et pas par lancement : sur la
  // version web PC, l'onglet reste ouvert des jours).
  static DateTime? _recapJour;

  @override
  void initState() {
    super.initState();
    // L'onglet vit dans un IndexedStack : il doit ecouter le modele
    // lui-meme pour que chips et blocs se rafraichissent immediatement.
    AppModel.instance.addListener(_surModele);
    WidgetsBinding.instance.addPostFrameCallback((_) => _proposerRecap());
  }

  @override
  void dispose() {
    AppModel.instance.removeListener(_surModele);
    super.dispose();
  }

  void _surModele() {
    if (mounted) setState(() {});
  }

  /// Kholles d'aujourd'hui deja terminees et sans note : le moment d'or du
  /// post-mortem (note, erreurs, ce qui est tombe).
  List<Colle> _khollesSansPostMortem(AppModel m, DateTime now) {
    return m.colles
        .where((c) =>
            c.start.year == now.year &&
            c.start.month == now.month &&
            c.start.day == now.day &&
            c.end.isBefore(now) &&
            c.note == null)
        .toList();
  }

  /// A l'ouverture : si des cours (ou des kholles !) d'aujourd'hui sont deja
  /// termines sans bilan, on propose directement le recap.
  Future<void> _proposerRecap() async {
    if (!mounted) return;
    final m = AppModel.instance;
    if (!m.loaded) return;
    final now = DateTime.now();
    final aujourdHui = DateTime(now.year, now.month, now.day);
    if (_recapJour == aujourdHui) return;
    final sansBilan = m.creneauxSansBilan(now);
    final kholles = _khollesSansPostMortem(m, now);
    if (sansBilan.isEmpty && kholles.isEmpty) return;
    _recapJour = aujourdHui;
    final total = sansBilan.length + kholles.length;
    final choisi = await feuilleAdaptative<Object>(
      context,
      (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                total == 1
                    ? 'Petit récap de ta journée ?'
                    : '$total moments de ta journée à récap ?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '10 secondes par créneau : ce qui a été fait nourrit ton plan du soir.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              for (final c in kholles)
                ListTile(
                  dense: true,
                  leading: const Text('🎤', style: TextStyle(fontSize: 18)),
                  title: Text('Khôlle ${c.matiere}'),
                  subtitle: Text(
                      '${frHeure(c.start)}${c.kholleur.isEmpty ? '' : ' · ${c.kholleur}'}',
                      style: const TextStyle(fontSize: 11)),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => Navigator.pop(context, c),
                ),
              for (final r in sansBilan)
                ListTile(
                  dense: true,
                  leading: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: Color(subjectColor(r.matiere)),
                        shape: BoxShape.circle),
                  ),
                  title: Text(r.titre),
                  subtitle: Text(r.labelHeure,
                      style: const TextStyle(fontSize: 11)),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => Navigator.pop(context, r),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Plus tard'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (choisi == null || !mounted) return;
    if (choisi is Routine) await _bilanSheet(choisi);
    if (choisi is Colle) await _postMortemKholle(choisi);
    // Il reste peut-etre d'autres moments a recap : on repropose.
    _recapJour = null;
    if (mounted) _proposerRecap();
  }

  /// POST-MORTEM d'une kholle (30 s) : la note si elle a ete donnee, une
  /// erreur au cahier, et — donnee precieuse — ce qui est TOMBE (ce qui
  /// tombe en colle annonce le DS). Stocke dans Colle.remarque.
  Future<void> _postMortemKholle(Colle c) async {
    final m = AppModel.instance;
    final tombeCtl = TextEditingController(text: c.remarque);
    await feuilleAdaptative<void>(
      context,
      (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Khôlle ${c.matiere} — comment ça s\'est passé ?',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.grade, size: 16),
                    label: Text(c.note == null
                        ? 'Saisir la note'
                        : 'Note : ${c.note}'),
                    onPressed: () async {
                      final n = await noteAvecRecalibrage(context,
                          matiere: c.matiere, current: c.note);
                      if (n != null) {
                        c.note = n < 0 ? null : n;
                        m.updateColle(c);
                      }
                    },
                  ),
                  ActionChip(
                    avatar: const Text('📕', style: TextStyle(fontSize: 14)),
                    label: const Text('Noter une erreur'),
                    onPressed: () =>
                        ajouterErreurDialog(context, matiere: c.matiere),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tombeCtl,
                maxLines: 2,
                minLines: 1,
                decoration: const InputDecoration(
                  labelText: 'Ce qui est tombé (facultatif)',
                  hintText: 'ex. question de cours Cauchy-Lipschitz + exo séries entières',
                  helperText:
                      'Ce qui tombe en colle annonce souvent le DS 😉',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () {
                    c.remarque = tombeCtl.text.trim();
                    m.updateColle(c);
                    Navigator.pop(context);
                  },
                  child: const Text('Terminé'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Dialog « coller le programme de colle » : appliqué a toutes les kholles
  /// de la matiere cette semaine-la, et partage avec la classe si code.
  Future<void> _collerProgramme(Colle c) async {
    final m = AppModel.instance;
    final ctl = TextEditingController(text: c.programme);
    var partager = m.codeClasse.isNotEmpty;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          title: Text('Programme — ${c.matiere}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Khôlle du ${frDateCourte(c.start)}. Colle le texte du programme (Cahier de prépa, mail, photo du tableau recopiée…).',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ctl,
                autofocus: true,
                maxLines: 5,
                minLines: 3,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: 'ex. Séries entières : rayon de convergence…',
                  suffixIcon: IconButton(
                    tooltip: 'Coller depuis le presse-papiers',
                    icon: const Icon(Icons.content_paste),
                    onPressed: () async {
                      final d = await Clipboard.getData('text/plain');
                      if (d?.text != null && d!.text!.trim().isNotEmpty) {
                        setDlg(() => ctl.text = d.text!.trim());
                      }
                    },
                  ),
                ),
              ),
              if (m.codeClasse.isNotEmpty)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('Partager avec ma classe (${m.codeClasse})',
                      style: const TextStyle(fontSize: 13)),
                  value: partager,
                  onChanged: (v) => setDlg(() => partager = v ?? true),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                final texte = ctl.text.trim();
                if (texte.isEmpty) return;
                m.definirProgramme(c.matiere, c.start, texte,
                    partager: partager);
                Navigator.pop(context);
                ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(
                    content: Text(partager && m.codeClasse.isNotEmpty
                        ? 'Programme enregistré et partagé avec ta classe ✅'
                        : 'Programme enregistré ✅')));
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  static const _durees = [
    (45, '45 min'),
    (60, '1 h'),
    (90, '1 h 30'),
    (120, '2 h'),
    (180, '3 h'),
  ];

  String _labelMin(int min) {
    if (min < 60) return '$min min';
    if (min % 60 == 0) return '${min ~/ 60} h';
    return '${min ~/ 60} h ${(min % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;
    final now = DateTime.now();
    final prochaine = m.prochaineColle();
    final budget = _budgetSoir(m, now);
    final suggestions = budget < 15 ? <Suggestion>[] : suggere(m, budget);
    final lundi = mondayOf(now);
    final dimanche = lundi.add(const Duration(days: 7));
    final semaineColles = m.colles
        .where((c) => c.start.isAfter(lundi) && c.start.isBefore(dimanche))
        .toList();
    final semaineDs = m.ds
        .where((d) => d.date.isAfter(lundi.subtract(const Duration(days: 1))) &&
            d.date.isBefore(dimanche))
        .toList();
    final aRendre = m.devoirsARendre().take(4).toList();
    final minSem = m.minutesSemaine();
    final edtJour = m.routinesLe(now);
    final evtsJour = m.evenementsLe(now);
    final plage = m.plageSansCours(now);

    final entete = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        '${frDate(now)[0].toUpperCase()}${frDate(now).substring(1)}'
        '${m.refSemaineA != null ? ' · semaine ${m.semaineEstA(now) ? 'A' : 'B'}' : ''}',
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: Colors.grey.shade600),
      ),
    );

    // Nudge programme de colle : une kholle dans ≤ 3 jours sans programme.
    Colle? sansProgramme;
    for (final c in m.collesAvenir()) {
      if (c.programme.trim().isEmpty && c.start.difference(now).inDays <= 3) {
        sansProgramme = c;
        break;
      }
    }

    final alertes = <Widget>[
      if (m.chargementEchoue)
        _banniere(
          Colors.red,
          Icons.error_outline,
          'Tes données n\'ont pas pu être lues au démarrage — rien n\'est écrasé, une copie de secours a été conservée. Restaure une sauvegarde (Réglages → Données) ou récupère ton compte.',
        ),
      if (m.syncConflit)
        _banniere(
          Colors.orange,
          Icons.sync_problem,
          'Ton autre appareil a des données plus récentes. Fais « Récupérer » dans Réglages → Compte avant de continuer ici, sinon rien ne sera synchronisé.',
        ),
      if (m.compteEnAvance && !m.syncConflit)
        _banniereAction(
          Colors.orange,
          Icons.cloud_sync,
          'Ton compte a des données plus récentes que cet appareil (poussées par ton autre appareil). Récupère-les AVANT de modifier ici.',
          'Récupérer',
          () async {
            try {
              final resume = await m.tirerCompte();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Récupéré ✅ ($resume)')));
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        'Échec : ${e.toString().replaceFirst('Exception: ', '')}')));
              }
            }
          },
        ),
      if (kIsWeb &&
          m.compteCle.isEmpty &&
          m.serverUrl.isNotEmpty &&
          (m.colles.isNotEmpty || m.chapitres.isNotEmpty))
        _banniereAction(
          Colors.indigo,
          Icons.cloud_off,
          'Sur navigateur, un simple « effacer les données de navigation » supprime tout. Un compte gratuit (2 taps, sans email) met ton semestre à l\'abri et synchronise avec ton téléphone.',
          'Créer',
          () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SettingsScreen())),
        ),
      if (m.dateConcours != null &&
          !m.dateConcours!.isAfter(now) &&
          !m.modeOraux)
        _banniereAction(
          Colors.deepPurple,
          Icons.school,
          'Tes écrits sont passés 🎉 La suite se joue à l\'oral — active le mode oraux : le plan du soir bascule en préparation d\'épreuves, tout à voix haute.',
          'Mode oraux',
          () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const OrauxScreen())),
        ),
      if (sansProgramme != null)
        _banniereAction(
          Colors.teal,
          Icons.assignment_outlined,
          'Ta khôlle de ${sansProgramme.matiere} est ${frJour(sansProgramme.start)} et n\'a pas de programme — colle-le ici (5 s), il servira aussi à ton plan du soir${m.codeClasse.isEmpty ? '' : ' et à toute ta classe'}.',
          'Coller',
          () => _collerProgramme(sansProgramme!),
        ),
    ];

    final gauche = <Widget>[
      _blocProchaine(prochaine),
      _blocARendre(aRendre, now),
      _blocSemaine(semaineColles, semaineDs, now),
    ];
    final droite = <Widget>[
      if (m.modeOraux && m.oraux.isNotEmpty)
        _blocOraux(m)
      else if (m.dateConcours != null && m.dateConcours!.isAfter(now))
        _blocConcours(m),
      _blocJournee(edtJour, evtsJour, plage),
      _blocHeures(minSem),
    ];
    final centre = _heroSoir(context, suggestions, minSem, budget);

    return LayoutBuilder(
      builder: (context, contraintes) {
        final vueSemaine = _blocVueSemaine(
            context, m, now, contraintes.maxWidth >= 1000);
        if (contraintes.maxWidth >= 900) {
          // ---- Cockpit large : gauche / CENTRE / droite + semaine dessous ----
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...alertes,
                entete,
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 280, child: Column(children: gauche)),
                    const SizedBox(width: 14),
                    Expanded(child: centre),
                    const SizedBox(width: 14),
                    SizedBox(width: 300, child: Column(children: droite)),
                  ],
                ),
                vueSemaine,
              ],
            ),
          );
        }
        // ---- Telephone : session du soir d'abord, blocs ensuite ----
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ...alertes,
            entete,
            centre,
            const SizedBox(height: 4),
            ...gauche,
            ...droite,
            vueSemaine,
          ],
        );
      },
    );
  }

  /// Minutes reellement disponibles ce soir : la duree choisie, plafonnee
  /// par l'heure limite de sommeil (logique pure et testee dans engine.dart
  /// — y compris apres minuit).
  int _budgetSoir(AppModel m, DateTime now) => budgetSoir(
        minutes: minutes,
        limiteMin: m.heureLimiteMin,
        nowMin: now.hour * 60 + now.minute,
      );

  /// Banniere avec un bouton d'action a droite.
  Widget _banniereAction(Color couleur, IconData icone, String texte,
      String labelBouton, VoidCallback onTap) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: couleur.withOpacity(0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: couleur.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icone, size: 20, color: couleur),
            const SizedBox(width: 10),
            Expanded(
              child: Text(texte,
                  style: const TextStyle(fontSize: 13, height: 1.3)),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: onTap,
              child: Text(labelBouton, style: const TextStyle(fontSize: 12.5)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _banniere(Color couleur, IconData icone, String texte) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: couleur.withOpacity(0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: couleur.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, size: 20, color: couleur),
            const SizedBox(width: 10),
            Expanded(
              child: Text(texte,
                  style: const TextStyle(fontSize: 13, height: 1.3)),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Carte a barre d'accent ----------

  Widget _carte({
    required Color accent,
    required IconData icone,
    required String titre,
    required Widget enfant,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withOpacity(0.25)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icone, size: 15, color: accent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            titre.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 0.5,
                                fontWeight: FontWeight.w700,
                                color: accent),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    enfant,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Blocs lateraux ----------

  Widget _blocProchaine(Colle? c) {
    if (c == null) {
      return _carte(
        accent: Colors.grey,
        icone: Icons.record_voice_over,
        titre: 'Prochaine khôlle',
        enfant: Text('Aucune à venir — importe ton colloscope.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
      );
    }
    final color = Color(subjectColor(c.matiere));
    final diff = c.start.difference(DateTime.now());
    final quand = diff.isNegative
        ? 'en cours'
        : diff.inHours < 36
            ? 'demain'
            : 'J-${diff.inDays + 1}';
    return _carte(
      accent: color,
      icone: Icons.record_voice_over,
      titre: 'Prochaine khôlle · $quand',
      enfant: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.matiere,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          Text(
            '${frDate(c.start)} · ${frHeure(c.start)}'
            '${c.salle.isEmpty ? '' : ' · salle ${c.salle}'}'
            '${c.kholleur.isEmpty ? '' : '\n${c.kholleur}'}',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
          ),
          if (c.programme.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('📋 ${c.programme}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.content_paste, size: 15),
                label: const Text('Coller le programme',
                    style: TextStyle(fontSize: 12)),
                onPressed: () => _collerProgramme(c),
              ),
            ),
        ],
      ),
    );
  }

  Widget _blocARendre(List<Devoir> aRendre, DateTime now) {
    return _carte(
      accent: Colors.orange,
      icone: Icons.assignment_turned_in_outlined,
      titre: 'À rendre',
      enfant: aRendre.isEmpty
          ? Text('Rien en attente 🎉',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final d in aRendre)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '${d.dateRendu.isBefore(DateTime(now.year, now.month, now.day)) ? '⚠ ' : ''}'
                      '${d.titre} ${d.matiere} — ${frDateCourte(d.dateRendu)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _blocSemaine(
      List<Colle> semaineColles, List<Ds> semaineDs, DateTime now) {
    return _carte(
      accent: Colors.indigo,
      icone: Icons.calendar_view_week_outlined,
      titre: 'Cette semaine',
      enfant: (semaineColles.isEmpty && semaineDs.isEmpty)
          ? Text('Rien au programme 🎉',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final c in semaineColles)
                  _miniLigne(
                    Color(subjectColor(c.matiere)),
                    'Khôlle ${c.matiere}',
                    '${frJour(c.start)} ${frHeure(c.start)}${c.salle.isEmpty ? '' : ' · s.${c.salle}'}',
                    c.end.isBefore(now),
                  ),
                for (final d in semaineDs)
                  _miniLigne(
                    Color(subjectColor(d.matiere)),
                    '${d.titre} ${d.matiere}',
                    frJour(d.date),
                    d.date
                        .isBefore(DateTime(now.year, now.month, now.day)),
                  ),
              ],
            ),
    );
  }

  Widget _blocConcours(AppModel m) {
    final jours = m.dateConcours!.difference(DateTime.now()).inDays + 1;
    final commences = m.chapitres.where((c) => c.etape > 0).length;
    final jamaisRevus = m.chapitres
        .where((c) => c.etape > 0 && c.dernierRevu == null)
        .length;
    return _carte(
      accent: Colors.deepPurple,
      icone: Icons.flag,
      titre: 'Concours',
      enfant: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('J-$jours',
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          Text(
            commences == 0
                ? 'Ajoute tes chapitres pour lancer la rotation.'
                : '$jamaisRevus/$commences chapitres jamais revus — le plan du soir les fait tourner.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget _blocOraux(AppModel m) {
    final prochain = m.prochainOral();
    final now = DateTime.now();
    return _carte(
      accent: Colors.deepPurple,
      icone: Icons.school,
      titre: 'Oraux',
      enfant: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (prochain == null)
            Text(
              '${m.oraux.length} épreuve(s) en rotation — les dates se rempliront après l\'admissibilité.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            )
          else ...[
            Text(
              'J-${DateTime(prochain.date!.year, prochain.date!.month, prochain.date!.day).difference(DateTime(now.year, now.month, now.day)).inDays}',
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(
              '${prochain.concours} — ${prochain.epreuve}, ${frDateCourte(prochain.date!)}'
              '${prochain.lieu.isEmpty ? '' : '\n📍 ${prochain.lieu}'}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ],
      ),
    );
  }

  Widget _blocJournee(
      List<Routine> edtJour, List<Evenement> evtsJour, PlageSansCours? plage) {
    // EDT + evenements ponctuels du jour, fusionnes et tries par heure.
    final lignes = <(int, Widget)>[
      if (plage == null)
        for (final r in edtJour) (r.debutMin, _ligneCreneau(context, r)),
      for (final e in evtsJour) (e.debutMin, _ligneEvenement(e)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return _carte(
      accent: Colors.amber.shade700,
      icone: Icons.wb_sunny_outlined,
      titre: 'Ta journée',
      enfant: (plage != null && lignes.isEmpty)
          ? Text('🏖 ${plage.titre} — pas de cours.',
              style: const TextStyle(fontSize: 13))
          : lignes.isEmpty
              ? Text(
                  'Rien à l\'emploi du temps. (Réglages → Mon emploi du temps.)',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (plage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('🏖 ${plage.titre} — pas de cours.',
                            style: const TextStyle(fontSize: 12.5)),
                      ),
                    for (final l in lignes) l.$2,
                  ],
                ),
    );
  }

  Widget _ligneEvenement(Evenement e) {
    final couleur = e.matiere.isEmpty
        ? Colors.blueGrey
        : Color(subjectColor(e.matiere));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(Icons.star, size: 12, color: couleur),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.titre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                Text(
                  '${e.labelHeure}${e.matiere.isEmpty ? '' : ' · ${e.matiere}'} · ponctuel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Vue semaine ----------

  Widget _blocVueSemaine(
      BuildContext context, AppModel m, DateTime now, bool etire) {
    // [etire] vient du LayoutBuilder de l'ecran : PAS de LayoutBuilder dans
    // la carte (IntrinsicHeight ne le supporte pas -> carte coupee).
    return _carte(
      accent: Colors.blueGrey,
      icone: Icons.view_week_outlined,
      titre: 'Ma semaine',
      enfant: VueSemaineColonnes(debut: mondayOf(now), etire: etire),
    );
  }

  Widget _blocHeures(Map<String, int> minSem) {
    final total = minSem[''] ?? 0;
    final parMatiere = minSem.entries
        .where((e) => e.key.isNotEmpty && e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxV = parMatiere.isEmpty ? 1 : parMatiere.first.value;
    return _carte(
      accent: Colors.teal,
      icone: Icons.timer_outlined,
      titre: 'Travail cette semaine',
      enfant: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(total == 0 ? '—' : _labelMin(total),
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          if (total == 0)
            Text('Coche tes sessions du soir pour compter.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          for (final e in parMatiere.take(4)) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                SizedBox(
                  width: 74,
                  child: Text(e.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5)),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: e.value / maxV,
                      minHeight: 6,
                      color: Color(subjectColor(e.key)),
                      backgroundColor: Colors.grey.withOpacity(0.15),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(_labelMin(e.value),
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniLigne(Color color, String titre, String sous, bool passe) {
    return Opacity(
      opacity: passe ? 0.45 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(titre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500)),
            ),
            Text(sous,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  // ---------- LE CENTRE : la session du soir ----------

  Widget _heroSoir(BuildContext context, List<Suggestion> suggestions,
      Map<String, int> minSem, int budget) {
    final m = AppModel.instance;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final plafonne = m.heureLimiteMin != null && budget < minutes;
    final hLim = m.heureLimiteMin ?? 0;
    final labelLim = '${hLim ~/ 60}h${(hLim % 60).toString().padLeft(2, '0')}';
    // Jour libre (week-end sans cours, vacances) : la JOURNEE remplace la
    // soiree — en-tete et presets de duree adaptes.
    final jourLibre = m.plageSansCours(now) != null ||
        (m.routines.isNotEmpty && m.routinesLe(now).isEmpty);
    final durees = jourLibre
        ? const [
            (90, '1 h 30'),
            (120, '2 h'),
            (180, '3 h'),
            (240, '4 h'),
            (360, 'Journée (6 h)'),
          ]
        : _durees;
    // DS passe ce matin (le samedi classique) : soiree legere recommandee.
    final dsPasseAujourdhui = now.hour >= 13 &&
        m.ds.any((d) =>
            d.date.year == now.year &&
            d.date.month == now.month &&
            d.date.day == now.day);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.primary.withOpacity(0.35), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(jourLibre ? Icons.wb_sunny : Icons.nightlight,
                    size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text(jourLibre ? 'Aujourd\'hui, tu as…' : 'Ce soir, tu as…',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            if (dsPasseAujourdhui)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '🎉 DS passé aujourd\'hui — sois indulgent avec toi-même, une soirée courte suffit largement.',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final e in durees)
                  ChoiceChip(
                    label: Text(e.$2),
                    selected: minutes == e.$1,
                    onSelected: (_) => setState(() => minutes = e.$1),
                  ),
                ChoiceChip(
                  label: Text(durees.any((e) => e.$1 == minutes)
                      ? 'Autre…'
                      : 'Autre : ${_labelMin(minutes)}'),
                  selected: !durees.any((e) => e.$1 == minutes),
                  onSelected: (_) => _dureePerso(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Méthode : ',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                for (final me in const [
                  ('checklist', '✅ Checklist'),
                  ('pomo25', '🍅 25/5'),
                  ('pomo50', '🍅 50/10'),
                  ('pomoAuto', '🍅 Auto'),
                ])
                  ChoiceChip(
                    label: Text(me.$2, style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                    selected: m.methodeTravail == me.$1,
                    onSelected: (_) => m.saveMethodeTravail(me.$1),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (plafonne)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  budget >= 15
                      ? '🌙 Plan ajusté pour finir avant $labelLim — le sommeil consolide ce que tu viens d\'apprendre.'
                      : '🌙 Il est presque $labelLim : dormir maintenant fera plus pour tes notes qu\'une heure de travail en plus. À demain !',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary),
                ),
              ),
            if (suggestions.isEmpty && !plafonne)
              Text(
                'Importe ton colloscope et ajoute quelques chapitres : je te proposerai un plan pour chaque soirée.',
                style: TextStyle(color: Colors.grey.shade600),
              )
            else if (m.methodeTravail == 'checklist')
              ...[for (final s in suggestions) _suggestionCard(context, s)]
            else
              ..._planPomodoro(context, suggestions),
            if ((minSem[''] ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Déjà travaillé cette semaine : ${_labelMin(minSem['']!)} 💪',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------- Duree personnalisee ----------

  Future<void> _dureePerso() async {
    final ctl = TextEditingController(text: minutes.toString());
    final v = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ce soir, en minutes'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              border: OutlineInputBorder(), hintText: 'ex. 75'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(ctl.text.trim())),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (v != null && v >= 15 && v <= 600) setState(() => minutes = v);
  }

  // ---------- Bilan de journee ----------

  Widget _ligneCreneau(BuildContext context, Routine r) {
    final m = AppModel.instance;
    final bilan = m.bilanPour(DateTime.now(), r.id);
    String? chapitreNom;
    if (bilan?.chapitreId != null) {
      final i = m.chapitres.indexWhere((c) => c.id == bilan!.chapitreId);
      if (i >= 0) chapitreNom = m.chapitres[i].nom;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: r.matiere.isEmpty
                  ? Colors.blueGrey
                  : Color(subjectColor(r.matiere)),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.titre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                Text(
                  bilan == null
                      ? r.labelHeure
                      : '${bilan.type}${chapitreNom == null ? '' : ' — $chapitreNom'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (r.matiere.isNotEmpty)
            bilan == null
                ? OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8)),
                    onPressed: () => _bilanSheet(r),
                    child:
                        const Text('Bilan ?', style: TextStyle(fontSize: 11)),
                  )
                : IconButton(
                    tooltip: 'Modifier le bilan',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.check_circle,
                        color: Colors.green, size: 18),
                    onPressed: () => _bilanSheet(r),
                  ),
        ],
      ),
    );
  }

  Future<void> _bilanSheet(Routine r) async {
    final m = AppModel.instance;
    await feuilleAdaptative<void>(
      context,
      (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${r.titre} — qu\'avez-vous fait ?',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.menu_book, size: 16),
                    label: const Text('Cours'),
                    onPressed: () {
                      Navigator.pop(context);
                      _choisirChapitre(r);
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.edit, size: 16),
                    label: const Text('Exos'),
                    onPressed: () {
                      m.setBilan(Bilan(
                          jour: DateTime.now(),
                          routineId: r.id,
                          matiere: r.matiere,
                          type: 'Exos'));
                      Navigator.pop(context);
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.science, size: 16),
                    label: const Text('TP'),
                    onPressed: () {
                      m.setBilan(Bilan(
                          jour: DateTime.now(),
                          routineId: r.id,
                          matiere: r.matiere,
                          type: 'TP'));
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Cours → tu choisiras le chapitre vu (et s\'il est fini ou encore en cours).',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const Divider(height: 20),
              Text('On vous a donné du travail ?',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700)),
              const SizedBox(height: 6),
              ActionChip(
                avatar: const Text('📥', style: TextStyle(fontSize: 14)),
                label: const Text('DM / exos à faire pour un prochain cours'),
                onPressed: () async {
                  final d = await editDevoirDialog(context,
                      matiere: r.matiere);
                  if (d != null) {
                    m.addDevoir(d);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                              '${d.titre} ${d.matiere} ajouté — rappelé sur le tableau de bord ✅')));
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Apres le choix du chapitre : le prof l'a FINI (-> etape "vu en cours"
  /// + revision espacee des demain) ou il est EN PLEIN DEDANS (-> juste
  /// marque "entamé", rien ne se declenche — un chapitre a moitié vu n'est
  /// pas un chapitre vu).
  Future<void> _finirBilanCours(Routine r, String chapitreId, String nom) async {
    final m = AppModel.instance;
    final termine = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(nom),
        content: const Text(
            'Le prof a fini ce chapitre, ou vous êtes en plein dedans ?\n\n'
            'Fini → la révision espacée démarre dès demain. En cours → rien ne se déclenche, tu le rediras quand il sera terminé.'),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('⏳ En plein dedans'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('✅ Fini'),
          ),
        ],
      ),
    );
    // Ferme sans repondre = prudence : on n'avance pas les etapes.
    m.setBilan(
      Bilan(
        jour: DateTime.now(),
        routineId: r.id,
        matiere: r.matiere,
        type: 'Cours',
        chapitreId: chapitreId,
      ),
      chapitreTermine: termine ?? false,
    );
  }

  Future<void> _choisirChapitre(Routine r) async {
    final m = AppModel.instance;
    final chapitres = m.chapitres.where((c) => c.matiere == r.matiere).toList();
    await feuilleAdaptative<void>(
      context,
      (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Quel chapitre a été vu en ${r.matiere} ?',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in chapitres)
                      ListTile(
                        dense: true,
                        title: Text(c.nom),
                        subtitle: c.entame && c.etape == 0
                            ? const Text('⏳ le prof est en plein dedans',
                                style: TextStyle(fontSize: 11))
                            : null,
                        onTap: () {
                          Navigator.pop(context);
                          _finirBilanCours(r, c.id, c.nom);
                        },
                      ),
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.add, size: 18),
                      title: const Text('Nouveau chapitre…'),
                      onTap: () async {
                        Navigator.pop(context);
                        await _nouveauChapitre(r);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _nouveauChapitre(Routine r) async {
    final ctl = TextEditingController();
    final nom = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Nouveau chapitre — ${r.matiere}'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
              border: OutlineInputBorder(), hintText: 'ex. Séries entières'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctl.text.trim()),
              child: const Text('OK')),
        ],
      ),
    );
    if (nom == null || nom.isEmpty) return;
    final m = AppModel.instance;
    final c = Chapitre(matiere: r.matiere, nom: nom, maitrise: 2, etape: 0);
    m.addChapitre(c);
    await _finirBilanCours(r, c.id, c.nom);
  }

  // ---------- Plan Pomodoro ----------

  /// Vocabulaire, langues, francais : blocs courts (25/5). Sciences : blocs
  /// longs (50/10), le temps d'entrer vraiment dans un exercice.
  bool _blocsCourts(String matiere) {
    final m = matiere.trim().toLowerCase();
    return m.contains('angl') ||
        m.contains('lv') ||
        m.contains('espagnol') ||
        m.contains('allemand') ||
        m.contains('fran') ||
        m.contains('philo') ||
        m.contains('lettres');
  }

  List<BlocPomodoro> _blocsPomodoro(List<Suggestion> suggestions) {
    final m = AppModel.instance;
    final blocs = <BlocPomodoro>[];
    for (final s in suggestions) {
      int travail, pause;
      if (m.methodeTravail == 'pomoAuto') {
        final courts = _blocsCourts(s.matiere);
        travail = courts ? 25 : 50;
        pause = courts ? 5 : 10;
      } else {
        travail = m.methodeTravail == 'pomo50' ? 50 : 25;
        pause = m.methodeTravail == 'pomo50' ? 10 : 5;
      }
      var reste = s.minutes;
      while (reste >= 15) {
        final w = reste >= travail ? travail : reste;
        if (blocs.isNotEmpty) {
          blocs.add(BlocPomodoro('Pause', '', pause, pause: true));
        }
        blocs.add(
            BlocPomodoro(s.titre, s.matiere, w, chapitreId: s.chapitreId));
        reste -= w;
      }
    }
    return blocs;
  }

  List<Widget> _planPomodoro(
      BuildContext context, List<Suggestion> suggestions) {
    final blocs = _blocsPomodoro(suggestions);
    var num = 0;
    return [
      FilledButton.icon(
        icon: const Icon(Icons.play_arrow),
        label: Text(
            'Lancer le minuteur (${blocs.where((b) => !b.pause).length} 🍅)'),
        onPressed: blocs.isEmpty
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => MinuteurScreen(blocs: blocs)),
                ),
      ),
      const SizedBox(height: 8),
      for (final b in blocs)
        b.pause
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('   ☕ Pause ${b.minutes} min',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              )
            : Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Colors.grey.withOpacity(0.25)),
                ),
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor:
                        Color(subjectColor(b.matiere)).withOpacity(0.18),
                    child: Text('${++num}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(subjectColor(b.matiere)))),
                  ),
                  title: Text('${b.matiere} · ${b.minutes} min',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: Text(b.label,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              ),
    ];
  }

  // ---------- Cartes du plan checklist ----------

  Widget _suggestionCard(BuildContext context, Suggestion s) {
    final color = Color(subjectColor(s.matiere));
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.withOpacity(0.25)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.18),
          child: Text(
            '${s.minutes >= 60 ? '${s.minutes ~/ 60}h' : ''}${s.minutes % 60 == 0 ? '' : (s.minutes % 60).toString().padLeft(2, '0')}',
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        title:
            Text(s.matiere, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${s.raison}\n${s.titre}'),
            if (s.consigne.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '💡 ${s.consigne}',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey.shade600),
                ),
              ),
          ],
        ),
        trailing: IconButton(
          tooltip: s.rappel
              ? 'Revu ! (règle la prochaine révision)'
              : 'Fait ! (enregistre la séance)',
          icon: const Icon(Icons.check_circle_outline),
          onPressed: () {
            if (s.rappel && s.chapitreId != null) {
              _evaluerRappel(s);
              return;
            }
            final m = AppModel.instance;
            m.addSeance(s.matiere, s.minutes);
            if (s.chapitreId != null) {
              final i = m.chapitres.indexWhere((c) => c.id == s.chapitreId);
              if (i >= 0) {
                m.chapitres[i].dernierRevu = DateTime.now();
                m.updateChapitre(m.chapitres[i]);
              }
            }
            // Bloc DM : le ✓ propose de marquer le devoir rendu.
            final iDev = s.devoirId == null
                ? -1
                : m.devoirs.indexWhere((d) => d.id == s.devoirId);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Séance ${s.matiere} enregistrée (+${_labelMin(s.minutes)}) ✅'),
              action: iDev >= 0 && !m.devoirs[iDev].rendu
                  ? SnackBarAction(
                      label: 'Rendu ?',
                      onPressed: () {
                        m.devoirs[iDev].rendu = true;
                        m.updateDevoir(m.devoirs[iDev]);
                      },
                    )
                  : null,
            ));
          },
        ),
      ),
    );
  }

  /// Auto-evaluation en 1 tap apres un rappel espace : la reponse regle
  /// l'ecart avant la prochaine revision (difficile -> vite, facile -> loin).
  Future<void> _evaluerRappel(Suggestion s) async {
    final m = AppModel.instance;
    final verdict = await feuilleAdaptative<String>(
      context,
      (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${s.matiere} — comment ça s\'est passé ?',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Ta réponse règle la date de la prochaine révision. Sois honnête, personne ne regarde 😉',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (final v in const [
                    ('difficile', '😮‍💨', 'Difficile'),
                    ('cava', '🙂', 'Ça va'),
                    ('facile', '😎', 'Facile'),
                  ]) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, v.$1),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            children: [
                              Text(v.$2,
                                  style: const TextStyle(fontSize: 24)),
                              const SizedBox(height: 2),
                              Text(v.$3,
                                  style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (v.$1 != 'facile') const SizedBox(width: 8),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (verdict == null) return;
    m.evaluerRevision(s.chapitreId!, verdict);
    m.addSeance(s.matiere, s.minutes);
    final i = m.chapitres.indexWhere((c) => c.id == s.chapitreId);
    final jours = i >= 0 ? m.chapitres[i].intervalleJours : 1;
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Revu ✅ Prochaine révision dans $jours j.'),
    ));
  }
}
