import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import 'erreurs.dart';

/// Sur telephone : bottom sheet classique. Sur GRAND ECRAN : boite de
/// dialogue centree — une sheet collee en bas de fenetre passe sous la
/// barre des taches Windows des que la fenetre la chevauche.
Future<T?> feuilleAdaptative<T>(
    BuildContext context, Widget Function(BuildContext) builder) {
  if (MediaQuery.of(context).size.width >= 900) {
    return showDialog<T>(
      context: context,
      builder: (context) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: builder(context),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
      context: context, isScrollControlled: true, builder: builder);
}

/// Dialogue "Ta clé de compte 🔑" apres creation d'un compte anonyme :
/// affiche la cle en grand + bouton Copier. [rappel] adapte la phrase de
/// contexte (onboarding vs Reglages). Partage entre les deux ecrans —
/// avant, le dialogue etait recopie mot pour mot.
Future<void> montrerCleCompte(BuildContext context, String cle,
    {required String rappel}) {
  return showDialog<void>(
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
                  fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'NOTE-LA précieusement : c\'est elle — et elle seule — qui permet '
            'de retrouver tes données sur un autre appareil ou après une '
            'réinstallation. $rappel',
            style: const TextStyle(fontSize: 13),
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
}

/// Dialogue de saisie d'une cle de compte existante (18 caracteres).
/// Retourne la cle saisie, ou null si annule.
Future<String?> demanderCleCompte(BuildContext context) {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Ma clé de compte'),
      content: TextField(
        controller: ctl,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(
            border: OutlineInputBorder(), hintText: '18 caractères'),
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
}

/// Feuille d'auto-evaluation en 1 tap apres une revision espacee.
/// Retourne 'difficile' | 'cava' | 'facile', ou null si fermee sans choix.
/// C'est la reponse de l'ELEVE qui regle l'intervalle — jamais le simple
/// fait d'avoir passe du temps sur le chapitre (illusion de maitrise).
Future<String?> demanderAutoEvaluation(BuildContext context, String titre) {
  return feuilleAdaptative<String>(
    context,
    (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titre, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Ta réponse règle la date de la prochaine révision. Sois honnête, personne ne regarde 😉',
              style: TextStyle(fontSize: 12, color: couleurSecondaire(context)),
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
                            Text(v.$2, style: const TextStyle(fontSize: 24)),
                            const SizedBox(height: 2),
                            Text(v.$3, style: const TextStyle(fontSize: 12)),
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
}

/// "45 min", "1 h", "1 h 30"...
String _labelDuree(int min) {
  if (min < 60) return '$min min';
  if (min % 60 == 0) return '${min ~/ 60} h';
  return '${min ~/ 60} h ${(min % 60).toString().padLeft(2, '0')}';
}

/// Editeur de khôlle (creation ou modification).
Future<Colle?> editColleDialog(BuildContext context, {Colle? initial}) async {
  final m = AppModel.instance;
  final matiereCtl = TextEditingController(text: initial?.matiere ?? '');
  final kholleurCtl = TextEditingController(text: initial?.kholleur ?? '');
  final salleCtl = TextEditingController(text: initial?.salle ?? '');
  final progCtl = TextEditingController(text: initial?.programme ?? '');
  var date = initial?.start ?? DateTime.now().add(const Duration(days: 1));
  var time = TimeOfDay(hour: initial?.start.hour ?? 16, minute: initial?.start.minute ?? 0);
  var duree = initial?.dureeMin ?? 60;

  return showDialog<Colle>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(initial == null ? 'Nouvelle khôlle' : 'Modifier la khôlle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: matiereCtl,
                decoration: const InputDecoration(labelText: 'Matière'),
                textCapitalization: TextCapitalization.sentences,
              ),
              if (m.matieres.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    children: [
                      for (final mat in m.matieres)
                        ActionChip(
                          label: Text(mat, style: const TextStyle(fontSize: 12)),
                          onPressed: () => setState(() => matiereCtl.text = mat),
                        ),
                    ],
                  ),
                ),
              TextField(
                controller: kholleurCtl,
                decoration: const InputDecoration(labelText: 'Khôlleur (facultatif)'),
              ),
              TextField(
                controller: salleCtl,
                decoration: const InputDecoration(labelText: 'Salle (facultatif)'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event, size: 18),
                      label: Text(frDateCourte(date)),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(2023),
                          lastDate: DateTime(2032),
                        );
                        if (d != null) setState(() => date = d);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text(time.format(context)),
                      onPressed: () async {
                        final t = await showTimePicker(context: context, initialTime: time);
                        if (t != null) setState(() => time = t);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Durée : '),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: duree,
                    // La valeur courante est toujours dans la liste, meme si
                    // l'import IA a donne une duree inhabituelle (45, 80 min...) :
                    // sans ca, Flutter plante ("exactly one item with value").
                    items: [
                      for (final d in ({30, 45, 55, 60, 90, 120, duree}.toList()..sort()))
                        DropdownMenuItem(value: d, child: Text(_labelDuree(d))),
                    ],
                    onChanged: (v) => setState(() => duree = v ?? 60),
                  ),
                ],
              ),
              TextField(
                controller: progCtl,
                decoration: const InputDecoration(labelText: 'Programme de colle (facultatif)'),
                maxLines: 3,
                minLines: 1,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (matiereCtl.text.trim().isEmpty) return;
              final start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
              final c = initial ?? Colle(matiere: '', start: start, custom: true);
              c
                ..matiere = normaliseMatiere(matiereCtl.text)
                ..kholleur = kholleurCtl.text.trim()
                ..salle = salleCtl.text.trim()
                ..start = start
                ..dureeMin = duree
                ..programme = progCtl.text.trim();
              Navigator.pop(context, c);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );
}

/// Editeur de DS.
Future<Ds?> editDsDialog(BuildContext context, {Ds? initial}) async {
  final m = AppModel.instance;
  final matiereCtl = TextEditingController(text: initial?.matiere ?? '');
  final titreCtl = TextEditingController(text: initial?.titre ?? 'DS');
  var date = initial?.date ?? DateTime.now().add(const Duration(days: 3));
  var coeff = initial?.coeff ?? 1.0;
  var interro = initial?.interro ?? false;
  final moyClasseCtl = TextEditingController(
      text: initial?.moyenneClasse?.toString() ?? '');

  return showDialog<Ds>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(initial == null ? 'Nouveau DS' : 'Modifier le DS'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: matiereCtl,
              decoration: const InputDecoration(labelText: 'Matière'),
            ),
            if (m.matieres.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (final mat in m.matieres)
                      ActionChip(
                        label: Text(mat, style: const TextStyle(fontSize: 12)),
                        onPressed: () => setState(() => matiereCtl.text = mat),
                      ),
                  ],
                ),
              ),
            TextField(
              controller: titreCtl,
              decoration: const InputDecoration(labelText: 'Titre (DS, concours blanc…)'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Petite interro de cours',
                  style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                  'Le plan te fait relire le COURS les jours d\'avant (coeff faible par défaut).',
                  style: TextStyle(fontSize: 11.5)),
              value: interro,
              onChanged: (v) => setState(() {
                interro = v;
                if (v) {
                  final t = titreCtl.text.trim();
                  if (t.isEmpty || t == 'DS') titreCtl.text = 'Interro';
                  coeff = 0.5;
                }
              }),
            ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              icon: const Icon(Icons.event, size: 18),
              label: Text(frDate(date)),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(2023),
                  lastDate: DateTime(2032),
                );
                if (d != null) setState(() => date = d);
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Coefficient : '),
                const SizedBox(width: 8),
                DropdownButton<double>(
                  value: coeff,
                  items: [
                    for (final c in ({0.5, 1.0, 1.5, 2.0, 3.0, coeff}.toList()
                      ..sort()))
                      DropdownMenuItem(
                          value: c,
                          child: Text(c == c.roundToDouble()
                              ? c.toInt().toString()
                              : c.toString())),
                  ],
                  onChanged: (v) => setState(() => coeff = v ?? 1.0),
                ),
              ],
            ),
            TextField(
              controller: moyClasseCtl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Moyenne de la classe (facultatif)',
                helperText:
                    'C\'est elle qui dit si une note est bonne — un 9 peut être au-dessus de la barre.',
                helperMaxLines: 2,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (matiereCtl.text.trim().isEmpty) return;
              final d = initial ?? Ds(matiere: '', date: date);
              final moyClasse = double.tryParse(
                  moyClasseCtl.text.replaceAll(',', '.'));
              d
                ..matiere = normaliseMatiere(matiereCtl.text)
                ..titre = titreCtl.text.trim().isEmpty ? 'DS' : titreCtl.text.trim()
                ..date = DateTime(date.year, date.month, date.day)
                ..coeff = coeff
                ..interro = interro
                ..moyenneClasse =
                    (moyClasse != null && moyClasse > 0 && moyClasse <= 20)
                        ? moyClasse
                        : null;
              Navigator.pop(context, d);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );
}

/// Editeur de devoir a rendre (DM / DNS / exos donnes en cours).
/// [matiere] pre-remplit la matiere (ex. depuis le recap d'un creneau).
Future<Devoir?> editDevoirDialog(BuildContext context,
    {Devoir? initial, String? matiere}) async {
  final m = AppModel.instance;
  final matiereCtl =
      TextEditingController(text: initial?.matiere ?? matiere ?? '');
  final titreCtl = TextEditingController(text: initial?.titre ?? 'DM');
  final remCtl = TextEditingController(text: initial?.remarque ?? '');
  var date = initial?.dateRendu ?? DateTime.now().add(const Duration(days: 7));

  return showDialog<Devoir>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(initial == null ? 'Devoir à rendre' : 'Modifier le devoir'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: matiereCtl,
                decoration: const InputDecoration(labelText: 'Matière'),
              ),
              if (m.matieres.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    children: [
                      for (final mat in m.matieres)
                        ActionChip(
                          label: Text(mat, style: const TextStyle(fontSize: 12)),
                          onPressed: () => setState(() => matiereCtl.text = mat),
                        ),
                    ],
                  ),
                ),
              TextField(
                controller: titreCtl,
                decoration:
                    const InputDecoration(labelText: 'Titre (DM 3, DNS, Exos…)'),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (final t in const ['DM', 'DNS', 'Exos'])
                      ActionChip(
                        label: Text(t, style: const TextStyle(fontSize: 12)),
                        onPressed: () => setState(() => titreCtl.text = t),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.event, size: 18),
                label: Text('À rendre le ${frDateCourte(date)}'),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2023),
                    lastDate: DateTime(2032),
                  );
                  if (d != null) setState(() => date = d);
                },
              ),
              TextField(
                controller: remCtl,
                decoration: const InputDecoration(
                    labelText: 'Remarque (facultatif — ex. exos 1 à 4)'),
                maxLines: 2,
                minLines: 1,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (matiereCtl.text.trim().isEmpty) return;
              final d = initial ?? Devoir(matiere: '', dateRendu: date);
              d
                ..matiere = normaliseMatiere(matiereCtl.text)
                ..titre =
                    titreCtl.text.trim().isEmpty ? 'DM' : titreCtl.text.trim()
                ..dateRendu = DateTime(date.year, date.month, date.day)
                ..remarque = remCtl.text.trim();
              Navigator.pop(context, d);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );
}

/// Editeur d'evenement ponctuel (sport aux dates annoncees tard, TP info
/// une semaine sur trois, oral blanc, sortie...).
Future<Evenement?> editEvenementDialog(BuildContext context,
    {Evenement? initial}) async {
  final m = AppModel.instance;
  final titreCtl = TextEditingController(text: initial?.titre ?? '');
  final matiereCtl = TextEditingController(text: initial?.matiere ?? '');
  var date = initial?.date ?? DateTime.now().add(const Duration(days: 1));
  var time = TimeOfDay(
      hour: (initial?.debutMin ?? 960) ~/ 60,
      minute: (initial?.debutMin ?? 960) % 60);
  var duree = initial?.dureeMin ?? 60;

  return showDialog<Evenement>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
            initial == null ? 'Événement ponctuel' : 'Modifier l\'événement'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titreCtl,
                decoration: const InputDecoration(
                    labelText: 'Titre (Sport, TP info, Oral blanc…)'),
                textCapitalization: TextCapitalization.sentences,
              ),
              TextField(
                controller: matiereCtl,
                decoration: const InputDecoration(
                  labelText: 'Matière (facultatif)',
                  helperText:
                      'Avec une matière, le plan du soir en tient compte.',
                  helperMaxLines: 2,
                ),
              ),
              if (m.matieres.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    children: [
                      for (final mat in m.matieres)
                        ActionChip(
                          label:
                              Text(mat, style: const TextStyle(fontSize: 12)),
                          onPressed: () =>
                              setState(() => matiereCtl.text = mat),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event, size: 18),
                      label: Text(frDateCourte(date)),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(2023),
                          lastDate: DateTime(2032),
                        );
                        if (d != null) setState(() => date = d);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text(time.format(context)),
                      onPressed: () async {
                        final t = await showTimePicker(
                            context: context, initialTime: time);
                        if (t != null) setState(() => time = t);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Durée : '),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: duree,
                    items: [
                      for (final d
                          in ({30, 60, 90, 120, 180, 240, duree}.toList()
                            ..sort()))
                        DropdownMenuItem(value: d, child: Text(_labelDuree(d))),
                    ],
                    onChanged: (v) => setState(() => duree = v ?? 60),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (titreCtl.text.trim().isEmpty) return;
              final e = initial ??
                  Evenement(titre: '', date: date, debutMin: 0);
              e
                ..titre = titreCtl.text.trim()
                ..matiere = normaliseMatiere(matiereCtl.text)
                ..date = DateTime(date.year, date.month, date.day)
                ..debutMin = time.hour * 60 + time.minute
                ..dureeMin = duree;
              Navigator.pop(context, e);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );
}

/// Saisie d'une note /20. Retourne -1 pour "effacer la note".
Future<double?> noteDialog(BuildContext context, {double? current}) async {
  final ctl = TextEditingController(text: current?.toString() ?? '');
  return showDialog<double>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Note /20'),
      content: TextField(
        controller: ctl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(hintText: 'ex. 14.5'),
      ),
      actions: [
        if (current != null)
          TextButton(
            onPressed: () => Navigator.pop(context, -1.0),
            child: const Text('Effacer'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            final v = double.tryParse(ctl.text.replaceAll(',', '.'));
            if (v != null && v >= 0 && v <= 20) Navigator.pop(context, v);
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Saisie de note + RECALIBRAGE : une mauvaise note est le meilleur signal
/// que des chapitres sont moins maitrises qu'on ne le pensait. Le seuil est
/// RELATIF quand la moyenne de classe est connue (en prepa, un 9 peut etre
/// au-dessus de la barre ; un 7 avec classe a 6 n'a rien d'alarmant),
/// absolu (< 8) sinon. Jamais culpabilisant.
Future<double?> noteAvecRecalibrage(BuildContext context,
    {required String matiere, double? current, double? moyenneClasse}) async {
  final note = await noteDialog(context, current: current);
  if (note == null || note < 0) return note;
  final seuil = moyenneClasse ?? 8;
  if (note >= seuil) return note;
  if (!context.mounted) return note;

  final m = AppModel.instance;
  final chs = m.chapitres
      .where((c) => c.matiere == matiere && c.etape > 0)
      .toList();
  if (chs.isEmpty) return note;

  final choisis = <String>{};
  await feuilleAdaptative<void>(
    context,
    (context) => StatefulBuilder(
      builder: (context, setState) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ça arrive à tout le monde 💪',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                'Quels chapitres t\'ont posé problème ? Ils repasseront en priorité dans ton plan du soir.',
                style: TextStyle(fontSize: 13, color: couleurSecondaire(context)),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final c in chs)
                        FilterChip(
                          label: Text(c.nom,
                              style: const TextStyle(fontSize: 12)),
                          selected: choisis.contains(c.id),
                          onSelected: (sel) => setState(() =>
                              sel ? choisis.add(c.id) : choisis.remove(c.id)),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  TextButton.icon(
                    icon: const Text('📕', style: TextStyle(fontSize: 14)),
                    label: const Text('Noter une erreur',
                        style: TextStyle(fontSize: 12)),
                    onPressed: () => ajouterErreurDialog(context,
                        matiere: matiere),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Passer'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: choisis.isEmpty
                        ? null
                        : () {
                            m.recalibrerChapitres(choisis.toList());
                            Navigator.pop(context);
                          },
                    child: const Text('Reprogrammer'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return note;
}

/// Reactivation d'ete (5/2) : si aucune plage « Ete » ne couvre aujourd'hui,
/// propose d'en creer une (aujourd'hui -> 31 aout) puis etale la revision
/// des chapitres commences sur les jours restants (etalerReactivation).
/// Affiche le snackbar de resultat. Retourne le nombre de chapitres
/// planifies, ou null si l'utilisateur a annule. Partagee entre Reglages
/// (Profil & scolarite), l'onboarding d'ete et le tableau de bord.
Future<int?> planifierReactivationEte(BuildContext context) async {
  final m = AppModel.instance;
  final now = DateTime.now();
  var plage = m.plageSansCours(now);
  if (plage == null || plage.type != 'ete') {
    final creer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pas de plage « Été » en cours'),
        content: Text(
            'La réactivation s\'étale sur une plage de grandes vacances. '
            'En créer une du ${now.day}/${now.month} au 31 août ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Créer la plage')),
        ],
      ),
    );
    if (creer != true || !context.mounted) return null;
    final fin = DateTime(now.month >= 9 ? now.year + 1 : now.year, 8, 31);
    m.addPlageSansCours(PlageSansCours(
      titre: 'Grandes vacances',
      debut: DateTime(now.year, now.month, now.day),
      fin: fin,
      type: 'ete',
    ));
  }
  final n = m.etalerReactivation();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 5),
      content: Text(n == 0
          ? 'Aucun chapitre commencé à planifier — importe d\'abord le programme officiel.'
          : 'Réactivation planifiée ✅ $n chapitres répartis jusqu\'à la fin des vacances — ils arriveront en « Rappel du jour ».'),
    ));
  }
  return n;
}
