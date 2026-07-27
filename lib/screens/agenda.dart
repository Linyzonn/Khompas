import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../ics.dart';
import '../models.dart';
import '../store.dart';
import 'dialogs.dart';
import 'import.dart';
import 'import_ds.dart';
import 'oraux.dart';

/// Onglet "Agenda" : toutes les khôlles et DS, groupes par semaine.
class AgendaScreen extends StatelessWidget {
  const AgendaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;
    final debut = mondayOf(DateTime.now());
    final events = <_Event>[
      for (final c in m.colles)
        if (!c.end.isBefore(debut)) _Event.colle(c),
      for (final d in m.ds)
        if (!d.date.isBefore(debut)) _Event.ds(d),
      // Un devoir non rendu reste visible meme en retard.
      for (final d in m.devoirs)
        if (!d.dateRendu.isBefore(debut) || !d.rendu) _Event.devoir(d),
      for (final e in m.evenements)
        if (!e.date.isBefore(debut)) _Event.evenement(e),
      for (final o in m.oraux)
        if (o.date != null && !o.date!.isBefore(debut)) _Event.oral(o),
    ]..sort((a, b) => a.date.compareTo(b.date));

    // Groupement par semaine (lundi).
    final Map<DateTime, List<_Event>> semaines = {};
    for (final e in events) {
      semaines.putIfAbsent(mondayOf(e.date), () => []).add(e);
    }
    final lundis = semaines.keys.toList()..sort();

    return Scaffold(
      body: events.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.calendar_month, size: 56, color: Colors.grey),
                    const SizedBox(height: 12),
                    const Text(
                      'Ton agenda est vide.\nImporte ton colloscope en une photo :',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      icon: const Icon(Icons.photo_camera),
                      label: const Text('Importer mon colloscope'),
                      onPressed: () => _openImport(context),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 90),
              children: [
                for (final lundi in lundis) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                    child: Text(
                      'Semaine du ${frDateCourte(lundi)}',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: Colors.grey.shade600),
                    ),
                  ),
                  for (final e in semaines[lundi]!) _tile(context, e),
                ],
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _menuAjout(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  static void _openImport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ImportScreen()),
    );
  }

  /// Exporte toutes les khôlles a venir en .ics -> agenda du telephone.
  static Future<void> exportIcs(BuildContext context) async {
    final m = AppModel.instance;
    final aVenir = m.collesAvenir();
    if (aVenir.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune khôlle à exporter.')),
      );
      return;
    }
    if (kIsWeb) {
      // Pas de partage de fichier dans le navigateur : on copie le contenu
      // du calendrier, a coller dans un fichier .ics.
      await Clipboard.setData(ClipboardData(text: buildIcs(aVenir)));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(seconds: 7),
          content: Text(
              'Calendrier copié ✅ Colle-le dans un fichier « kholles.ics », puis importe-le dans ton agenda (Google Agenda : Paramètres → Importer).'),
        ));
      }
      return;
    }
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/kholles-khompas.ics');
    await f.writeAsString(buildIcs(aVenir));
    await Share.shareXFiles(
      [XFile(f.path, mimeType: 'text/calendar')],
      text:
          'Mes khôlles — ouvre ce fichier pour les ajouter à ton calendrier (rappel 1h avant inclus).',
    );
  }

  void _menuAjout(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.record_voice_over),
              title: const Text('Ajouter une khôlle'),
              subtitle: const Text('Rattrapage, colle ponctuelle…'),
              onTap: () async {
                Navigator.pop(context);
                final c = await editColleDialog(context);
                if (c != null) AppModel.instance.addColles([c]);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_document),
              title: const Text('Ajouter un DS'),
              onTap: () async {
                Navigator.pop(context);
                final d = await editDsDialog(context);
                if (d != null) AppModel.instance.addDs(d);
              },
            ),
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: const Text('Ajouter un événement ponctuel'),
              subtitle: const Text('Sport, TP info, oral blanc, sortie…'),
              onTap: () async {
                Navigator.pop(context);
                final ev = await editEvenementDialog(context);
                if (ev != null) AppModel.instance.addEvenement(ev);
              },
            ),
            ListTile(
              leading: const Icon(Icons.assignment_turned_in),
              title: const Text('Ajouter un DM / DNS à rendre'),
              onTap: () async {
                Navigator.pop(context);
                final d = await editDevoirDialog(context);
                if (d != null) AppModel.instance.addDevoir(d);
              },
            ),
            ListTile(
              leading: const Icon(Icons.event_note),
              title: const Text('Importer un planning de DS (IA, gratuit)'),
              subtitle: const Text('Tous les DS du semestre en une fois'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ImportDsScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Importer un colloscope (photo + IA)'),
              onTap: () {
                Navigator.pop(context);
                _openImport(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, _Event e) {
    final m = AppModel.instance;
    final color = Color(subjectColor(e.matiere));
    if (e.colle != null) {
      final c = e.colle!;
      return ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.18),
          child: Icon(Icons.record_voice_over, color: color, size: 20),
        ),
        title: Text('Khôlle ${c.matiere}'),
        subtitle: Text(
          '${frJour(c.start)} ${c.start.day} · ${frHeure(c.start)}'
          '${c.salle.isEmpty ? '' : ' · salle ${c.salle}'}'
          '${c.kholleur.isEmpty ? '' : ' · ${c.kholleur}'}'
          '${c.programme.isEmpty ? '' : '\n📋 ${c.programme}'}',
        ),
        isThreeLine: c.programme.isNotEmpty,
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'edit') {
              final edited = await editColleDialog(context, initial: c);
              if (edited != null) m.updateColle(edited);
            } else if (v == 'note') {
              final n = await noteAvecRecalibrage(context,
                  matiere: c.matiere, current: c.note);
              if (n != null) {
                c.note = n < 0 ? null : n;
                m.updateColle(c);
              }
            } else if (v == 'delete') {
              m.deleteColle(c.id);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Modifier / programme')),
            const PopupMenuItem(value: 'note', child: Text('Saisir la note')),
            const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
          ],
        ),
      );
    }
    if (e.evenement != null) {
      final ev = e.evenement!;
      return ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.18),
          child: Icon(Icons.star_outline, color: color, size: 20),
        ),
        title: Text(ev.titre),
        subtitle: Text(
          '${frJour(ev.date)} ${ev.date.day} · ${ev.labelHeure}'
          '${ev.matiere.isEmpty ? '' : ' · ${ev.matiere}'}',
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'edit') {
              final edited = await editEvenementDialog(context, initial: ev);
              if (edited != null) m.updateEvenement(edited);
            } else if (v == 'delete') {
              m.deleteEvenement(ev.id);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Modifier')),
            const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
          ],
        ),
      );
    }
    if (e.oral != null) {
      final o = e.oral!;
      return ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.18),
          child: Icon(Icons.school, color: color, size: 20),
        ),
        title: Text('Oral ${o.concours} — ${o.epreuve}'),
        subtitle: Text(
          '${frJour(o.date!)} ${o.date!.day}'
          '${o.debutMin == null ? '' : ' · ${o.debutMin! ~/ 60}h${(o.debutMin! % 60).toString().padLeft(2, '0')}'}'
          '${o.lieu.isEmpty ? '' : ' · ${o.lieu}'}',
        ),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const OrauxScreen())),
      );
    }
    if (e.devoir != null) {
      final d = e.devoir!;
      final enRetard = !d.rendu &&
          d.dateRendu.isBefore(DateTime.now().subtract(const Duration(days: 1)));
      return ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.18),
          child: Icon(Icons.assignment_turned_in, color: color, size: 20),
        ),
        title: Text(
          '${d.titre} ${d.matiere}',
          style: d.rendu
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: Text(
          '${enRetard ? '⚠ ' : ''}À rendre ${frDate(d.dateRendu)}'
          '${d.remarque.isEmpty ? '' : '\n${d.remarque}'}',
        ),
        isThreeLine: d.remarque.isNotEmpty,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: d.rendu,
              onChanged: (v) {
                d.rendu = v ?? false;
                m.updateDevoir(d);
              },
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'edit') {
                  final edited = await editDevoirDialog(context, initial: d);
                  if (edited != null) m.updateDevoir(edited);
                } else if (v == 'delete') {
                  m.deleteDevoir(d.id);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Modifier')),
                const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
              ],
            ),
          ],
        ),
      );
    }
    final d = e.ds!;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.18),
        child: Icon(Icons.edit_document, color: color, size: 20),
      ),
      title: Text('${d.titre} ${d.matiere}'
          '${d.coeff == 1 ? '' : ' · coef ${d.coeff == d.coeff.roundToDouble() ? d.coeff.toInt() : d.coeff}'}'),
      subtitle: Text(frDate(d.date)),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'edit') {
            final edited = await editDsDialog(context, initial: d);
            if (edited != null) m.updateDs(edited);
          } else if (v == 'note') {
            final n = await noteAvecRecalibrage(context,
                matiere: d.matiere, current: d.note);
            if (n != null) {
              d.note = n < 0 ? null : n;
              m.updateDs(d);
            }
          } else if (v == 'delete') {
            m.deleteDs(d.id);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Modifier')),
          const PopupMenuItem(value: 'note', child: Text('Saisir la note')),
          const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
        ],
      ),
    );
  }
}

class _Event {
  final DateTime date;
  final String matiere;
  final Colle? colle;
  final Ds? ds;
  final Devoir? devoir;
  final Evenement? evenement;
  final EpreuveOrale? oral;
  _Event.colle(Colle c)
      : date = c.start,
        matiere = c.matiere,
        colle = c,
        ds = null,
        devoir = null,
        evenement = null,
        oral = null;
  _Event.ds(Ds d)
      : date = d.date,
        matiere = d.matiere,
        colle = null,
        ds = d,
        devoir = null,
        evenement = null,
        oral = null;
  _Event.devoir(Devoir d)
      : date = d.dateRendu,
        matiere = d.matiere,
        colle = null,
        ds = null,
        devoir = d,
        evenement = null,
        oral = null;
  _Event.evenement(Evenement e)
      : date = e.date,
        matiere = e.matiere.isEmpty ? e.titre : e.matiere,
        colle = null,
        ds = null,
        devoir = null,
        evenement = e,
        oral = null;
  _Event.oral(EpreuveOrale o)
      : date = o.date!,
        matiere = o.epreuve,
        colle = null,
        ds = null,
        devoir = null,
        evenement = null,
        oral = o;
}
