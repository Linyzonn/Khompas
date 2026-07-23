import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import 'dialogs.dart';

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

    return ListView(
      padding: const EdgeInsets.only(bottom: 90),
      children: [
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

  Color _tendColor(double ecart) {
    if (ecart >= 0.5) return Colors.green;
    if (ecart <= -0.5) return Colors.redAccent;
    return Colors.grey;
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
    final now = DateTime.now();
    final collesPassees = m.colles
        .where((c) => c.matiere == mat && c.start.isBefore(now))
        .toList()
      ..sort((a, b) => b.start.compareTo(a.start));
    final dsMat = m.ds.where((d) => d.matiere == mat).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return ExpansionTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.18),
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
              child: Icon(_tendIcon(t.$1), size: 18, color: _tendColor(t.$1)),
            ),
        ],
      ),
      subtitle: Text(
        'Khôlles : ${mc == null ? '—' : mc.toStringAsFixed(1)}/20'
        '   ·   DS : ${md == null ? '—' : md.toStringAsFixed(1)}/20',
        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
      ),
      children: [
        if (t != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              '${_tendLabel(t.$1)} : ${t.$2.toStringAsFixed(1)}/20 sur les 3 dernières notes, '
              'contre ${t.$3.toStringAsFixed(1)}/20 en moyenne générale.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
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
              final n = await noteDialog(context, current: c.note);
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
            title: Text('${d.titre} du ${frDateCourte(d.date)}'),
            trailing: _noteChip(context, d.note, color, () async {
              final n = await noteDialog(context, current: d.note);
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

  Widget _noteChip(BuildContext context, double? note, Color color, VoidCallback onTap) {
    return ActionChip(
      onPressed: onTap,
      backgroundColor: note == null ? null : color.withOpacity(0.15),
      side: BorderSide(color: color.withOpacity(0.4)),
      label: Text(
        note == null
            ? '+ note'
            : '${note.toStringAsFixed(note == note.roundToDouble() ? 0 : 1)}/20',
        style: TextStyle(
          color: note == null ? Colors.grey.shade600 : color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
