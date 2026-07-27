import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'notifs.dart';
import 'screens/agenda.dart';
import 'screens/chapters.dart';
import 'screens/grades.dart';
import 'screens/import.dart';
import 'screens/onboarding.dart';
import 'screens/settings.dart';
import 'screens/today.dart';
import 'store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppModel.instance.load();
  // Chaque changement de donnees replanifie les notifications (veille de
  // kholle / oral / DM), avec un debounce pour grouper les rafales.
  if (!kIsWeb) {
    Timer? debounce;
    AppModel.instance.addListener(() {
      debounce?.cancel();
      debounce = Timer(const Duration(seconds: 5), () {
        Notifs.replanifier(AppModel.instance);
      });
    });
  }
  runApp(const KhompasApp());
}

class KhompasApp extends StatelessWidget {
  const KhompasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Khompas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6B5CEB)),
      ),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Gate(),
    );
  }
}

/// Aiguillage de demarrage : chargement -> ecran de bienvenue (premier
/// lancement) -> app.
class Gate extends StatelessWidget {
  const Gate({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppModel.instance,
      builder: (context, _) {
        final m = AppModel.instance;
        if (!m.loaded) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (!m.onboarded) return const OnboardingScreen();
        return const RootScaffold();
      },
    );
  }
}

class RootScaffold extends StatefulWidget {
  const RootScaffold({super.key});

  @override
  State<RootScaffold> createState() => _RootScaffoldState();
}

class _RootScaffoldState extends State<RootScaffold> {
  int tab = 0;

  static const titres = ["Aujourd'hui", 'Agenda', 'Notes', 'Chapitres'];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppModel.instance,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(titres[tab]),
          actions: [
            if (tab == 1) ...[
              IconButton(
                tooltip: 'Importer un colloscope',
                icon: const Icon(Icons.photo_camera_outlined),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ImportScreen())),
              ),
              IconButton(
                tooltip: "Exporter vers l'agenda du téléphone",
                icon: const Icon(Icons.ios_share),
                onPressed: () => AgendaScreen.exportIcs(context),
              ),
            ],
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
          ],
        ),
        body: IndexedStack(
          index: tab,
          children: const [
            TodayScreen(),
            AgendaScreen(),
            GradesScreen(),
            ChaptersScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.today_outlined),
                selectedIcon: Icon(Icons.today),
                label: "Aujourd'hui"),
            NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: 'Agenda'),
            NavigationDestination(
                icon: Icon(Icons.grade_outlined),
                selectedIcon: Icon(Icons.grade),
                label: 'Notes'),
            NavigationDestination(
                icon: Icon(Icons.school_outlined),
                selectedIcon: Icon(Icons.school),
                label: 'Chapitres'),
          ],
        ),
      ),
    );
  }
}
