import 'package:flutter/material.dart';

import '../engine.dart';
import '../models.dart';
import '../store.dart';
import 'minuteur.dart';

/// Onglet "Aujourd'hui" : le TABLEAU DE BORD de la journee de prepa.
/// De haut en bas : compte a rebours concours, prochaine kholle, la journee
/// (emploi du temps du jour + bilan par creneau), le plan du soir (duree
/// libre + methode checklist/pomodoro), les devoirs a rendre, la semaine.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  int minutes = 120;

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
    final suggestions = suggere(m, minutes);
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
    final plage = m.plageSansCours(now);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---- En-tete ----
        Text(
          '${frDate(now)[0].toUpperCase()}${frDate(now).substring(1)}'
          '${m.refSemaineA != null ? ' · semaine ${m.semaineEstA(now) ? 'A' : 'B'}' : ''}',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 10),
        // ---- Tuiles du tableau de bord (2 par ligne) ----
        LayoutBuilder(
          builder: (context, contraintes) {
            final w = (contraintes.maxWidth - 10) / 2;
            final joursConcours = m.dateConcours == null
                ? null
                : m.dateConcours!.difference(now).inDays + 1;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (prochaine != null)
                  _tuile(
                    w,
                    Color(subjectColor(prochaine.matiere)),
                    Icons.record_voice_over,
                    'Prochaine khôlle',
                    prochaine.matiere,
                    '${frJour(prochaine.start)} ${frHeure(prochaine.start)}'
                    '${prochaine.salle.isEmpty ? '' : ' · salle ${prochaine.salle}'}',
                  )
                else
                  _tuile(w, Colors.grey, Icons.record_voice_over,
                      'Prochaine khôlle', '—', 'importe ton colloscope'),
                if (joursConcours != null && joursConcours > 0)
                  _tuile(w, Colors.deepPurple, Icons.flag, 'Concours',
                      'J-$joursConcours', 'avant les écrits')
                else
                  _tuile(
                    w,
                    Colors.teal,
                    Icons.timer_outlined,
                    'Cette semaine',
                    _labelMin(minSem[''] ?? 0),
                    'de travail perso',
                  ),
                _tuile(
                  w,
                  Colors.orange,
                  Icons.assignment_turned_in_outlined,
                  'À rendre',
                  '${aRendre.length}',
                  aRendre.isEmpty
                      ? 'rien en attente 🎉'
                      : '${aRendre.first.titre} ${aRendre.first.matiere} ${frDateCourte(aRendre.first.dateRendu)}',
                ),
                _tuile(
                  w,
                  Colors.indigo,
                  Icons.school_outlined,
                  'Cette semaine',
                  '${semaineColles.length + semaineDs.length}',
                  'khôlles et DS',
                ),
              ],
            );
          },
        ),
        if (m.dateConcours != null && m.dateConcours!.isAfter(now)) ...[
          const SizedBox(height: 10),
          _concoursBanner(context, m),
        ],

        // ---- Ta journee (EDT du jour + bilans) ----
        const SizedBox(height: 20),
        _titre(context, Icons.wb_sunny_outlined, 'Ta journée'),
        const SizedBox(height: 8),
        if (plage != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text('🏖 ${plage.titre} — pas de cours. '
                  'Le plan du soir reste à ton service.'),
            ),
          )
        else if (edtJour.isEmpty)
          Text(
            'Rien dans ton emploi du temps aujourd\'hui. '
            '(Réglages → Mon emploi du temps pour le remplir.)',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [for (final r in edtJour) _ligneCreneau(context, r)],
              ),
            ),
          ),

        // ---- Ce soir ----
        const SizedBox(height: 20),
        _titre(context, Icons.nightlight_outlined, 'Ce soir, tu as…'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final e in _durees)
              ChoiceChip(
                label: Text(e.$2),
                selected: minutes == e.$1,
                onSelected: (_) => setState(() => minutes = e.$1),
              ),
            ChoiceChip(
              label: Text(_durees.any((e) => e.$1 == minutes)
                  ? 'Autre…'
                  : 'Autre : ${_labelMin(minutes)}'),
              selected: !_durees.any((e) => e.$1 == minutes),
              onSelected: (_) => _dureePerso(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('Méthode : ',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(width: 4),
            for (final me in const [
              ('checklist', '✅ Checklist'),
              ('pomo25', '🍅 25/5'),
              ('pomo50', '🍅 50/10'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(me.$2, style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                  selected: m.methodeTravail == me.$1,
                  onSelected: (_) => m.saveMethodeTravail(me.$1),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (suggestions.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Importe ton colloscope et ajoute quelques chapitres : je te proposerai un plan de travail pour chaque soirée.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
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

        // ---- A rendre ----
        if (aRendre.isNotEmpty) ...[
          const SizedBox(height: 20),
          _titre(context, Icons.assignment_turned_in_outlined, 'À rendre'),
          const SizedBox(height: 8),
          for (final d in aRendre)
            _miniEvent(
              color: Color(subjectColor(d.matiere)),
              titre:
                  '${d.dateRendu.isBefore(DateTime(now.year, now.month, now.day)) ? '⚠ ' : ''}${d.titre} ${d.matiere}',
              sousTitre: 'à rendre ${frDate(d.dateRendu)}',
              passe: false,
            ),
        ],

        // ---- Cette semaine ----
        const SizedBox(height: 20),
        _titre(context, Icons.calendar_view_week_outlined, 'Cette semaine'),
        const SizedBox(height: 8),
        if (semaineColles.isEmpty && semaineDs.isEmpty)
          Text('Rien au programme cette semaine 🎉',
              style: TextStyle(color: Colors.grey.shade600)),
        for (final c in semaineColles)
          _miniEvent(
            color: Color(subjectColor(c.matiere)),
            titre: 'Khôlle ${c.matiere}',
            sousTitre:
                '${frJour(c.start)} ${frHeure(c.start)}${c.salle.isEmpty ? '' : ' · salle ${c.salle}'}',
            passe: c.end.isBefore(now),
          ),
        for (final d in semaineDs)
          _miniEvent(
            color: Color(subjectColor(d.matiere)),
            titre: '${d.titre} ${d.matiere}',
            sousTitre: frDate(d.date),
            passe: d.date.isBefore(DateTime(now.year, now.month, now.day)),
          ),
      ],
    );
  }

  Widget _tuile(double largeur, Color couleur, IconData icone, String titre,
      String valeur, String sous) {
    return SizedBox(
      width: largeur,
      child: Card(
        margin: EdgeInsets.zero,
        color: couleur.withOpacity(0.10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icone, size: 15, color: couleur),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(titre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: couleur)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(valeur,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(sous,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _titre(BuildContext context, IconData icone, String texte) {
    return Row(
      children: [
        Icon(icone, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Text(texte, style: Theme.of(context).textTheme.titleMedium),
      ],
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
    return ListTile(
      dense: true,
      leading: r.matiere.isEmpty
          ? const Icon(Icons.loop, size: 18)
          : CircleAvatar(
              radius: 12,
              backgroundColor:
                  Color(subjectColor(r.matiere)).withOpacity(0.18),
              child: Text(
                r.matiere.characters.first.toUpperCase(),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(subjectColor(r.matiere))),
              ),
            ),
      title: Text(r.titre),
      subtitle: Text(
        bilan == null
            ? r.labelHeure
            : '${r.labelHeure} · ${bilan.type}${chapitreNom == null ? '' : ' — $chapitreNom'}',
      ),
      trailing: r.matiere.isEmpty
          ? null
          : bilan == null
              ? OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  onPressed: () => _bilanSheet(r),
                  child: const Text('Bilan ?', style: TextStyle(fontSize: 12)),
                )
              : IconButton(
                  tooltip: 'Modifier le bilan',
                  icon: const Icon(Icons.check_circle,
                      color: Colors.green, size: 20),
                  onPressed: () => _bilanSheet(r),
                ),
    );
  }

  Future<void> _bilanSheet(Routine r) async {
    final m = AppModel.instance;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
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
                'Cours → tu choisiras le chapitre vu : il passera en « vu en cours » et le plan du soir proposera de le revoir.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _choisirChapitre(Routine r) async {
    final m = AppModel.instance;
    final chapitres = m.chapitres.where((c) => c.matiere == r.matiere).toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
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
                        subtitle: c.etape == 0
                            ? const Text('nouveau — passera en « vu en cours »',
                                style: TextStyle(fontSize: 11))
                            : null,
                        onTap: () {
                          m.setBilan(Bilan(
                            jour: DateTime.now(),
                            routineId: r.id,
                            matiere: r.matiere,
                            type: 'Cours',
                            chapitreId: c.id,
                          ));
                          Navigator.pop(context);
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
    final c = Chapitre(matiere: r.matiere, nom: nom, maitrise: 2, etape: 1);
    m.addChapitre(c);
    m.setBilan(Bilan(
      jour: DateTime.now(),
      routineId: r.id,
      matiere: r.matiere,
      type: 'Cours',
      chapitreId: c.id,
    ));
  }

  // ---------- Plan Pomodoro ----------

  List<BlocPomodoro> _blocsPomodoro(List<Suggestion> suggestions) {
    final m = AppModel.instance;
    final travail = m.methodeTravail == 'pomo50' ? 50 : 25;
    final pause = m.methodeTravail == 'pomo50' ? 10 : 5;
    final blocs = <BlocPomodoro>[];
    for (final s in suggestions) {
      var reste = s.minutes;
      while (reste >= 15) {
        final w = reste >= travail ? travail : reste;
        if (blocs.isNotEmpty) {
          blocs.add(BlocPomodoro('Pause', '', pause, pause: true));
        }
        blocs.add(BlocPomodoro(s.titre, s.matiere, w,
            chapitreId: s.chapitreId));
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

  // ---------- Cartes ----------

  Widget _concoursBanner(BuildContext context, AppModel m) {
    final jours = m.dateConcours!.difference(DateTime.now()).inDays + 1;
    final commences = m.chapitres.where((c) => c.etape > 0).length;
    final jamaisRevus = m.chapitres
        .where((c) => c.etape > 0 && c.dernierRevu == null)
        .length;
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Text('🎯', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('J-$jours avant les écrits',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(
                    commences == 0
                        ? 'Ajoute tes chapitres pour lancer la rotation.'
                        : '$jamaisRevus chapitre(s) sur $commences encore jamais revus — le plan du soir les fait tourner.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _suggestionCard(BuildContext context, Suggestion s) {
    final color = Color(subjectColor(s.matiere));
    return Card(
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
        subtitle: Text('${s.raison}\n${s.titre}'),
        isThreeLine: true,
        trailing: IconButton(
          tooltip: 'Fait ! (enregistre la séance)',
          icon: const Icon(Icons.check_circle_outline),
          onPressed: () {
            final m = AppModel.instance;
            m.addSeance(s.matiere, s.minutes);
            if (s.chapitreId != null) {
              final i = m.chapitres.indexWhere((c) => c.id == s.chapitreId);
              if (i >= 0) {
                m.chapitres[i].dernierRevu = DateTime.now();
                m.updateChapitre(m.chapitres[i]);
              }
            }
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Séance ${s.matiere} enregistrée (+${_labelMin(s.minutes)}) ✅'),
            ));
          },
        ),
      ),
    );
  }

  Widget _miniEvent({
    required Color color,
    required String titre,
    required String sousTitre,
    required bool passe,
  }) =>
      Opacity(
        opacity: passe ? 0.45 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titre,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    Text(sousTitre,
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
              ),
              if (passe) const Icon(Icons.check, size: 16, color: Colors.grey),
            ],
          ),
        ),
      );
}
