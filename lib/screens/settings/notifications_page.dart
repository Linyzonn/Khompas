import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../notifs.dart';
import '../../store.dart';
import '../../theme.dart';

/// Sous-page Reglages : notifications (veille de kholle / DM) et heure
/// limite de sommeil. Sur web, seule la partie Sommeil existe.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  // ---------- Heure limite de sommeil ----------

  Future<void> _choisirHeureLimite() async {
    final m = AppModel.instance;
    final actuel = m.heureLimiteMin ?? 23 * 60;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: actuel ~/ 60, minute: actuel % 60),
      helpText: 'Heure limite de travail le soir',
    );
    if (t != null) {
      m.setHeureLimite(t.hour * 60 + t.minute);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;
    return Scaffold(
      appBar: AppBar(
          title: const Text(kIsWeb ? 'Sommeil' : 'Notifications & sommeil')),
      body: listeCentree(context, children: [
          if (!kIsWeb) ...[
            Text('Notifications',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: kEsp4),
            Text(
              'Des rappels la VEILLE au soir (19 h), et uniquement ça — pas de spam. (Sur la version web PC, les notifications n\'existent pas.)',
              style: styleMeta(context),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Activer les notifications'),
              value: m.notifsActives,
              onChanged: (v) async {
                if (v) {
                  final ok = await Notifs.demanderPermission();
                  if (!ok) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'Permission refusée — autorise Khompas dans les réglages du téléphone.')));
                    }
                    return;
                  }
                }
                await m.setPrefsNotifs(actives: v);
                await Notifs.replanifier(m);
                if (mounted) setState(() {});
              },
            ),
            if (m.notifsActives) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Veille de khôlle / d\'oral'),
                subtitle: const Text(
                    'Matière, heure, salle et programme si connu.',
                    style: TextStyle(fontSize: 12)),
                value: m.notifVeilleKholle,
                onChanged: (v) async {
                  await m.setPrefsNotifs(veilleKholle: v);
                  await Notifs.replanifier(m);
                  if (mounted) setState(() {});
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Veille de DM / DNS à rendre'),
                subtitle: const Text('Le filet anti-oubli.',
                    style: TextStyle(fontSize: 12)),
                value: m.notifVeilleDm,
                onChanged: (v) async {
                  await m.setPrefsNotifs(veilleDm: v);
                  await Notifs.replanifier(m);
                  if (mounted) setState(() {});
                },
              ),
            ],
            const SizedBox(height: kEsp24),
          ],
          Text('Sommeil', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: kEsp4),
          Text(
            'Fixe une heure limite : le plan du soir se raccourcit tout seul '
            'pour finir avant. Le sommeil consolide la mémoire — travailler '
            'jusqu\'à 1h du matin fait perdre plus qu\'il ne fait gagner.',
            style: styleMeta(context),
          ),
          const SizedBox(height: kEsp8),
          if (m.heureLimiteMin == null)
            OutlinedButton.icon(
              icon: const Icon(Icons.bedtime_outlined),
              label: const Text('Fixer une heure limite'),
              onPressed: _choisirHeureLimite,
            )
          else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bedtime),
              title: Text(
                  'Heure limite : ${m.heureLimiteMin! ~/ 60}h${(m.heureLimiteMin! % 60).toString().padLeft(2, '0')}'),
              subtitle: const Text('Appuie pour changer.'),
              onTap: _choisirHeureLimite,
              trailing: TextButton(
                onPressed: () {
                  m.setHeureLimite(null);
                  setState(() {});
                },
                child: const Text('Retirer'),
              ),
            ),
        ],
      ),
    );
  }
}
