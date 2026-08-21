import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import 'bilan_concours.dart';
import 'dialogs.dart';
import 'erreurs.dart';

/// Onglet "Notes" : notes de khôlles et de DS, moyennes et tendance par matiere.
class GradesScreen extends StatelessWidget {
  const GradesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;
    final matieres = m.matieres;

    if (matieres.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Tes notes de khôlles et de DS apparaîtront ici.\nCommence par importer ton colloscope.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final aRefaire = m.erreurs.where((e) => !e.refaite).length;
    return ListView(
      padding: const EdgeInsets.only(bottom: 90),
      children: [
        ListTile(
          leading: const Text('📕', style: TextStyle(fontSize: 22)),
          title: const Text('Cahier d\'erreurs',
              style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            aRefaire == 0
                ? 'Note tes erreurs de khôlle/DS — refais-les jusqu\'à les maîtriser.'
                : '$aRefaire erreur(s) à refaire',
            style: TextStyle(fontSize: 12, color: couleurSecondaire(context)),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ErreursScreen())),
        ),
        if (m.cinqDemi)
          ListTile(
            leading: const Text('🎯', style: TextStyle(fontSize: 22)),
            title: const Text('Bilan de concours (5/2)',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              m.resultatsConcours.isEmpty
                  ? 'Tes notes de l\'an dernier par épreuve → où tu perds des points.'
                  : '${m.resultatsConcours.length} résultat(s) saisi(s)',
              style: TextStyle(fontSize: 12, color: couleurSecondaire(context)),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const BilanConcoursScreen())),
          ),
        const Divider(height: 1),
        for (final mat in matieres) _section(context, mat),
      ],
    );
  }

  /// Tendance d'une matiere : (ecart, moyenne des 3 dernieres notes, moyenne
  /// globale), toutes notes confondues (khôlles + DS), dans l'ordre du temps.
  /// null s'il y a moins de 4 notes (pas de tendance fiable avant).
  (double, double, double)? _tendance(String mat) {
    final m = AppModel.instance;
    final entries = <(DateTime, double)>[
      for (final c in m.colles)
        if (c.matiere == mat && c.note != null) (c.start, c.note!),
      for (final d in m.ds)
        if (d.matiere == mat && d.note != null) (d.date, d.note!),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    if (entries.length < 4) return null;
    final notes = [for (final e in entries) e.$2];
    final avgAll = notes.reduce((a, b) => a + b) / notes.length;
    final last3 = notes.sublist(notes.length - 3);
    final avg3 = last3.reduce((a, b) => a + b) / 3;
    return (avg3 - avgAll, avg3, avgAll);
  }

  IconData _tendIcon(double ecart) {
    if (ecart >= 0.5) return Icons.trending_up;
    if (ecart <= -0.5) return Icons.trending_down;
    return Icons.trending_flat;
  }

  Color _tendColor(BuildContext context, double ecart) {
    if (ecart >= 0.5) return context.tokens.succes;
    // Une baisse n'est PAS une alerte rouge : l'app ne culpabilise pas.
    if (ecart <= -0.5) return context.tokens.attention;
    return couleurSecondaire(context);
  }

  String _tendLabel(double ecart) {
    if (ecart >= 0.5) return '📈 En progrès';
    if (ecart <= -0.5) return '📉 En baisse';
    return '➡️ Stable';
  }

  Widget _section(BuildContext context, String mat) {
    final m = AppModel.instance;
    final color = Color(subjectColor(mat));
    final mc = m.moyenneColles(mat);
    final md = m.moyenneDs(mat);
    final t = _tendance(mat);
    final obj = m.objectifs[mat];
    // Moyenne globale ponderee : les khôlles comptent coeff 1, les DS leur
    // coefficient (un concours blanc coeff 3 pese 3 fois plus).
    final pondere = <(double, double)>[
      for (final c in m.colles)
        if (c.matiere == mat && c.note != null) (c.note!, 1.0),
      for (final d in m.ds)
        if (d.matiere == mat && d.note != null) (d.note!, d.coeff),
    ];
    final sommeCoeffs =
        pondere.fold<double>(0, (s, e) => s + e.$2);
    final avgGlobal = sommeCoeffs == 0
        ? null
        : pondere.fold<double>(0, (s, e) => s + e.$1 * e.$2) / sommeCoeffs;
    final now = DateTime.now();
    final collesPassees = m.colles
        .where((c) => c.matiere == mat && c.start.isBefore(now))
        .toList()
      ..sort((a, b) => b.start.compareTo(a.start));
    final dsMat = m.ds.where((d) => d.matiere == mat).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return ExpansionTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.18),
        child: Text(mat.characters.first.toUpperCase(),
            style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(mat, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (t != null)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(_tendIcon(t.$1), size: 18, color: _tendColor(context, t.$1)),
            ),
          IconButton(
            tooltip: 'Objectif de moyenne (facultatif)',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              obj == null ? Icons.flag_outlined : Icons.flag,
              size: 18,
              color: obj == null ? couleurSecondaire(context) : color,
            ),
            onPressed: () => _objectifDialog(context, mat, avgGlobal),
          ),
        ],
      ),
      subtitle: Text(
        'Khôlles : ${mc == null ? '—' : mc.toStringAsFixed(1)}/20'
        '   ·   DS : ${md == null ? '—' : md.toStringAsFixed(1)}/20',
        style: TextStyle(color: couleurSecondaire(context), fontSize: 12),
      ),
      children: [
        if (t != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              '${_tendLabel(t.$1)} : ${t.$2.toStringAsFixed(1)}/20 sur les 3 dernières notes, '
              'contre ${t.$3.toStringAsFixed(1)}/20 en moyenne générale.',
              style: TextStyle(fontSize: 12, color: couleurSecondaire(context)),
            ),
          ),
        if (obj != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              _ligneObjectif(obj, avgGlobal),
              style: TextStyle(fontSize: 12, color: couleurSecondaire(context)),
            ),
          ),
        if (collesPassees.isEmpty && dsMat.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Rien à noter pour le moment.'),
          ),
        for (final c in collesPassees)
          ListTile(
            dense: true,
            leading: const Icon(Icons.record_voice_over, size: 18),
            title: Text('Khôlle du ${frDateCourte(c.start)}'
                '${c.kholleur.isEmpty ? '' : ' · ${c.kholleur}'}'),
            trailing: _noteChip(context, c.note, color, () async {
              final n = await noteAvecRecalibrage(context,
                  matiere: c.matiere, current: c.note);
              if (n != null) {
                c.note = n < 0 ? null : n;
                AppModel.instance.updateColle(c);
              }
            }),
          ),
        for (final d in dsMat)
          ListTile(
            dense: true,
            leading: const Icon(Icons.edit_document, size: 18),
            title: Text('${d.titre} du ${frDateCourte(d.date)}'
                '${d.coeff == 1 ? '' : ' · coef ${d.coeff == d.coeff.roundToDouble() ? d.coeff.toInt() : d.coeff}'}'),
            subtitle: d.moyenneClasse == null || d.note == null
                ? null
                : Text(
                    'classe : ${d.moyenneClasse!.toStringAsFixed(1)} — tu es '
                    '${d.note! >= d.moyenneClasse! + 1 ? 'au-dessus 💪' : d.note! >= d.moyenneClasse! - 1 ? 'dans la moyenne' : 'un peu en dessous — ça se rattrape'}',
                    style: TextStyle(
                        fontSize: 11, color: couleurSecondaire(context))),
            trailing: _noteChip(context, d.note, color, () async {
              final n = await noteAvecRecalibrage(context,
                  matiere: d.matiere,
                  current: d.note,
                  moyenneClasse: d.moyenneClasse);
              if (n != null) {
                d.note = n < 0 ? null : n;
                AppModel.instance.updateDs(d);
              }
            }),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Ajouter un DS dans cette matière'),
            onPressed: () async {
              final d = await editDsDialog(context);
              if (d != null) AppModel.instance.addDs(d);
            },
          ),
        ),
      ],
    );
  }

  String _fmt(double v) => v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);

  /// Toujours formule en positif : un objectif doit motiver, pas demoraliser.
  String _ligneObjectif(double obj, double? avg) {
    if (avg == null) {
      return '🎯 Objectif ${_fmt(obj)}/20 — saisis tes premières notes pour suivre ta route.';
    }
    if (avg >= obj) {
      return '🎯 Objectif ${_fmt(obj)}/20 atteint (${_fmt(avg)}) — bravo ! Tu peux viser un cran plus haut.';
    }
    final ecart = obj - avg;
    if (ecart <= 1) {
      return '🎯 ${_fmt(avg)} → ${_fmt(obj)} : plus que ${_fmt(ecart)} pt, ça se joue sur une khôlle.';
    }
    return '🎯 Cap sur ${_fmt(obj)}/20 — chapitre par chapitre, sans pression.';
  }

  Future<void> _objectifDialog(
      BuildContext context, String mat, double? avg) async {
    final m = AppModel.instance;
    // Suggestion volontairement REALISTE : moyenne actuelle + 0,5 point
    // (un objectif inatteignable demoralise plus qu'il ne motive).
    final suggestion = m.objectifs[mat] ??
        (avg == null ? 12.0 : (((avg + 0.5) * 2).roundToDouble() / 2).clamp(1.0, 20.0));
    final ctl = TextEditingController(text: _fmt(suggestion));
    final existant = m.objectifs[mat] != null;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Objectif — $mat'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              avg == null
                  ? 'Facultatif. Un objectif réaliste motive ; un objectif inatteignable démoralise.'
                  : 'Facultatif. Suggestion réaliste : ta moyenne actuelle (${_fmt(avg)}) + 0,5. Un objectif inatteignable démoralise plus qu\'il ne motive.',
              style: TextStyle(fontSize: 13, color: couleurSecondaire(context)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Objectif /20', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          if (existant)
            TextButton(
              onPressed: () {
                m.setObjectif(mat, null);
                Navigator.pop(context);
              },
              child: const Text('Retirer'),
            ),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(ctl.text.replaceAll(',', '.'));
              if (v != null && v > 0 && v <= 20) {
                m.setObjectif(mat, v);
                Navigator.pop(context);
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _noteChip(BuildContext context, double? note, Color color, VoidCallback onTap) {
    return ActionChip(
      onPressed: onTap,
      backgroundColor: note == null ? null : color.withValues(alpha: 0.15),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      label: Text(
        note == null
            ? '+ note'
            : '${note.toStringAsFixed(note == note.roundToDouble() ? 0 : 1)}/20',
        style: TextStyle(
          color: note == null ? couleurSecondaire(context) : color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
