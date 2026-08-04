import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import 'settings/compte_page.dart';
import 'settings/concours_page.dart';
import 'settings/donnees_page.dart';
import 'settings/notifications_page.dart';
import 'settings/planning_page.dart';
import 'settings/profil_page.dart';

/// Les Reglages en HUB : une liste courte de categories, chacune ouvrant sa
/// sous-page (lib/screens/settings/). L'ancienne page unique empilait ~12
/// sections sur 1200 lignes — introuvable. Les sous-titres resument l'etat
/// (mode invite, date des ecrits...) et se rafraichissent au retour grace
/// au ListenableBuilder.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Widget _tuile(BuildContext context,
      {required IconData icone,
      required String titre,
      required String sousTitre,
      required Widget Function() page}) {
    return ListTile(
      leading: Icon(icone),
      title: Text(titre),
      subtitle: Text(sousTitre,
          style: TextStyle(fontSize: 12, color: couleurSecondaire(context))),
      trailing: const Icon(Icons.chevron_right),
      onTap: () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => page())),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppModel.instance,
      builder: (context, _) {
        final m = AppModel.instance;
        return Scaffold(
          appBar: AppBar(title: const Text('Réglages')),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _tuile(
                context,
                icone: Icons.person_outline,
                titre: 'Profil & scolarité',
                sousTitre:
                    '${m.filiere} · groupe ${m.groupe}${m.cinqDemi ? ' · 5/2' : ''}',
                page: () => const ProfilPage(),
              ),
              _tuile(
                context,
                icone: Icons.cloud_outlined,
                titre: 'Compte & synchronisation',
                sousTitre: m.compteCle.isEmpty
                    ? 'Mode invité — données locales uniquement'
                    : 'Connecté · clé ${m.compteCle.substring(0, 6)}…',
                page: () => const ComptePage(),
              ),
              _tuile(
                context,
                icone: Icons.calendar_month_outlined,
                titre: 'Planning & matières',
                sousTitre: 'Emploi du temps, calendrier, priorités, fusion',
                page: () => const PlanningPage(),
              ),
              _tuile(
                context,
                icone: Icons.flag_outlined,
                titre: 'Concours & oraux',
                sousTitre: m.modeOraux
                    ? 'Mode oraux ACTIF'
                    : m.dateConcours != null
                        ? 'Écrits le ${frDateCourte(m.dateConcours!)}'
                        : 'Écrits, annales, œuvres, TIPE, oraux',
                page: () => const ConcoursPage(),
              ),
              _tuile(
                context,
                icone: kIsWeb
                    ? Icons.bedtime_outlined
                    : Icons.notifications_outlined,
                titre: kIsWeb ? 'Sommeil' : 'Notifications & sommeil',
                sousTitre: kIsWeb
                    ? 'Heure limite du soir'
                    : '${m.notifsActives ? 'Notifications actives' : 'Notifications coupées'}'
                        '${m.heureLimiteMin != null ? ' · limite ${m.heureLimiteMin! ~/ 60}h${(m.heureLimiteMin! % 60).toString().padLeft(2, '0')}' : ''}',
                page: () => const NotificationsPage(),
              ),
              _tuile(
                context,
                icone: Icons.storage_outlined,
                titre: 'Données & avancé',
                sousTitre: 'Sauvegarde, restauration, remise à zéro, serveur',
                page: () => const DonneesPage(),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Khompas — bêta 0.16'),
                subtitle: Text(
                    'Le compagnon de ta prépa. Tes données restent sur ton téléphone.'),
              ),
            ],
          ),
        );
      },
    );
  }
}
