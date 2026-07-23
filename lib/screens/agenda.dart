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
              final n = await noteDialog(context, current: c.note);
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
    final d = e.ds!;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.18),
        child: Icon(Icons.edit_document, color: color, size: 20),
      ),
      title: Text('${d.titre} ${d.matiere}'),
      subtitle: Text(frDate(d.date)),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'edit') {
            final edited = await editDsDialog(context, initial: d);
            if (edited != null) m.updateDs(edited);
          } else if (v == 'note') {
            final n = await noteDialog(context, current: d.note);
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
  _Event.colle(Colle c)
      : date = c.start,
        matiere = c.matiere,
        colle = c,
        ds = null;
  _Event.ds(Ds d)
      : date = d.date,
        matiere = d.matiere,
        colle = null,
        ds = d;
}
