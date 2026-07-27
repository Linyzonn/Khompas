import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';
import 'store.dart';

/// Notifications LOCALES (telephone uniquement — rien n'existe sur le web) :
/// la veille a 19 h, un rappel pour chaque kholle / oral du lendemain et
/// chaque DM a rendre le lendemain. Tout est replanifie a chaque changement
/// de donnees : pas d'etat a maintenir, pas de notification fantome.
class Notifs {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initFait = false;

  static Future<void> _init() async {
    if (_initFait || kIsWeb) return;
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {
      // Zone introuvable : on retombe sur Paris (le public de l'app).
      try {
        tz.setLocalLocation(tz.getLocation('Europe/Paris'));
      } catch (_) {}
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // La permission est demandee explicitement au moment ou
          // l'utilisateur active les notifs (pas au premier lancement).
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _initFait = true;
  }

  /// Demande la permission systeme. Retourne true si accordee.
  static Future<bool> demanderPermission() async {
    if (kIsWeb) return false;
    await _init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(
              alert: true, badge: true, sound: true) ??
          false;
    }
    return false;
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'veilles',
      'Veilles d\'échéances',
      channelDescription:
          'Rappels la veille au soir : khôlle ou oral demain, DM à rendre.',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
    iOS: DarwinNotificationDetails(),
  );

  /// Annule tout puis replanifie selon l'etat actuel des donnees.
  /// Appele au demarrage et (debounce) apres chaque modification.
  static Future<void> replanifier(AppModel m) async {
    if (kIsWeb) return;
    try {
      await _init();
      await _plugin.cancelAll();
      if (!m.notifsActives) return;

      final now = DateTime.now();
      var id = 1;

      // 19 h la veille de l'evenement (ou dans 2 min si c'est deja passe
      // mais que l'evenement est demain — mieux vaut tard que jamais).
      tz.TZDateTime? veilleDe(DateTime evenement) {
        final v = DateTime(
            evenement.year, evenement.month, evenement.day - 1, 19, 0);
        final quand = v.isAfter(now)
            ? v
            : evenement.isAfter(now.add(const Duration(hours: 2)))
                ? now.add(const Duration(minutes: 2))
                : null;
        if (quand == null) return null;
        return tz.TZDateTime.from(quand, tz.local);
      }

      Future<void> planifier(DateTime evt, String titre, String corps) async {
        final quand = veilleDe(evt);
        if (quand == null || id > 60) return; // iOS plafonne a 64 en attente
        await _plugin.zonedSchedule(
          id: id++,
          title: titre,
          body: corps,
          scheduledDate: quand,
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }

      if (m.notifVeilleKholle) {
        for (final c in m.collesAvenir()) {
          await planifier(
            c.start,
            'Khôlle demain — ${c.matiere}',
            '${frHeure(c.start)}'
            '${c.salle.isEmpty ? '' : ' · salle ${c.salle}'}'
            '${c.kholleur.isEmpty ? '' : ' · ${c.kholleur}'}'
            '${c.programme.isEmpty ? '' : '\n📋 ${c.programme}'}',
          );
        }
        for (final o in m.oraux) {
          if (o.date == null || o.date!.isBefore(now)) continue;
          await planifier(
            o.date!,
            'Oral demain — ${o.concours}',
            '${o.epreuve}'
            '${o.debutMin == null ? '' : ' · ${o.debutMin! ~/ 60}h${(o.debutMin! % 60).toString().padLeft(2, '0')}'}'
            '${o.lieu.isEmpty ? '' : ' · ${o.lieu}'}',
          );
        }
      }

      if (m.notifVeilleDm) {
        for (final d in m.devoirsARendre()) {
          if (d.dateRendu.isBefore(now)) continue;
          await planifier(
            d.dateRendu,
            'À rendre demain — ${d.matiere}',
            '${d.titre}${d.remarque.isEmpty ? '' : ' · ${d.remarque}'}',
          );
        }
      }
    } catch (_) {
      // Les notifs ne doivent JAMAIS faire planter l'app (plugin absent
      // sur une plateforme, permission revoquee...).
    }
  }
}
