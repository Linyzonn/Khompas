import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'models.dart';

/// Serveur Khompas par defaut (celui de la beta) : les camarades n'ont
/// aucune URL a configurer. Modifiable dans Reglages.
const String kServeurDefaut = 'https://khompas.linyzonn.deno.net';

/// Etat global de l'app, persiste dans un fichier JSON local.
/// (La cle API, plus sensible, vit dans SharedPreferences.)
class AppModel extends ChangeNotifier {
  static final AppModel instance = AppModel._();
  AppModel._();

  List<Colle> colles = [];
  List<Ds> ds = [];
  List<Chapitre> chapitres = [];
  List<Routine> routines = [];
  List<Devoir> devoirs = [];
  List<Seance> seances = [];
  List<Bilan> bilans = [];
  List<Evenement> evenements = [];
  // Calendrier interne : periodes sans cours (vacances, semaines de
  // revisions) + lundi de reference d'une "semaine A" pour le roulement A/B.
  List<PlageSansCours> sansCours = [];
  DateTime? refSemaineA;
  // Methode de travail du soir : 'checklist' | 'pomo25' | 'pomo50'.
  String methodeTravail = 'checklist';
  // Objectif de moyenne par matiere (facultatif, toujours formule en positif).
  Map<String, double> objectifs = {};
  // Date des ecrits : non nulle = MODE REVISIONS CONCOURS actif.
  DateTime? dateConcours;
  String filiere = 'PCSI';
  int groupe = 1;
  // Code de partage du colloscope de ma classe (serveur Khompas).
  String codeClasse = '';
  // Priorite par matiere (1 a 3) : ponderation du plan de travail.
  Map<String, int> prios = {};

  String apiKey = '';
  // URL du serveur Khompas (beta) — vide = fonctions serveur masquees.
  String serverUrl = '';
  // Cle du compte anonyme (18 caracteres) — vide = pas de compte.
  String compteCle = '';
  // 5/2 : refait sa 2e annee -> adapte l'import du programme (chapitres
  // deja vus) et, plus tard, le plan de travail.
  bool cinqDemi = false;
  // Premier lancement termine (ecran de bienvenue passe) ?
  bool onboarded = false;
  bool loaded = false;

  Timer? _pushTimer;

  // ---------- Persistance ----------

  Future<File> _dbFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/khompas.json');
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      apiKey = prefs.getString('apiKey') ?? '';
      serverUrl = prefs.getString('serverUrl') ?? kServeurDefaut;
      compteCle = prefs.getString('compteCle') ?? '';
      onboarded = prefs.getBool('onboarded') ?? false;
      String? raw;
      if (kIsWeb) {
        // Version web (PC) : pas de systeme de fichiers, la base vit dans
        // le stockage local du navigateur (via SharedPreferences).
        raw = prefs.getString('db');
      } else {
        final f = await _dbFile();
        if (await f.exists()) raw = await f.readAsString();
      }
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        colles = ((j['colles'] ?? []) as List)
            .map((e) => Colle.fromJson(e as Map<String, dynamic>))
            .toList();
        ds = ((j['ds'] ?? []) as List)
            .map((e) => Ds.fromJson(e as Map<String, dynamic>))
            .toList();
        chapitres = ((j['chapitres'] ?? []) as List)
            .map((e) => Chapitre.fromJson(e as Map<String, dynamic>))
            .toList();
        routines = ((j['routines'] ?? []) as List)
            .map((e) => Routine.fromJson(e as Map<String, dynamic>))
            .toList();
        devoirs = ((j['devoirs'] ?? []) as List)
            .map((e) => Devoir.fromJson(e as Map<String, dynamic>))
            .toList();
        seances = ((j['seances'] ?? []) as List)
            .map((e) => Seance.fromJson(e as Map<String, dynamic>))
            .toList();
        objectifs = ((j['objectifs'] ?? {}) as Map)
            .map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
        dateConcours = j['dateConcours'] == null
            ? null
            : DateTime.tryParse(j['dateConcours'] as String);
        bilans = ((j['bilans'] ?? []) as List)
            .map((e) => Bilan.fromJson(e as Map<String, dynamic>))
            .toList();
        evenements = ((j['evenements'] ?? []) as List)
            .map((e) => Evenement.fromJson(e as Map<String, dynamic>))
            .toList();
        sansCours = ((j['sansCours'] ?? []) as List)
            .map((e) => PlageSansCours.fromJson(e as Map<String, dynamic>))
            .toList();
        refSemaineA = j['refSemaineA'] == null
            ? null
            : DateTime.tryParse(j['refSemaineA'] as String);
        methodeTravail = (j['methodeTravail'] ?? 'checklist') as String;
        filiere = (j['filiere'] ?? 'PCSI') as String;
        groupe = (j['groupe'] ?? 1) as int;
        codeClasse = (j['codeClasse'] ?? '') as String;
        cinqDemi = (j['cinqDemi'] ?? false) as bool;
        prios = ((j['prios'] ?? {}) as Map)
            .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
      }
    } catch (_) {
      // fichier corrompu : on repart proprement plutot que de planter
    }
    loaded = true;
    notifyListeners();
  }

  Map<String, dynamic> _snapshot() => {
        'app': 'khompas',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'colles': colles.map((c) => c.toJson()).toList(),
        'ds': ds.map((d) => d.toJson()).toList(),
        'chapitres': chapitres.map((c) => c.toJson()).toList(),
        'routines': routines.map((r) => r.toJson()).toList(),
        'devoirs': devoirs.map((d) => d.toJson()).toList(),
        'seances': seances.map((s) => s.toJson()).toList(),
        'objectifs': objectifs,
        'dateConcours': dateConcours?.toIso8601String(),
        'bilans': bilans.map((b) => b.toJson()).toList(),
        'evenements': evenements.map((e) => e.toJson()).toList(),
        'sansCours': sansCours.map((p) => p.toJson()).toList(),
        'refSemaineA': refSemaineA?.toIso8601String(),
        'methodeTravail': methodeTravail,
        'filiere': filiere,
        'groupe': groupe,
        'codeClasse': codeClasse,
        'cinqDemi': cinqDemi,
        'prios': prios,
      };

  Future<void> save() async {
    try {
      final raw = jsonEncode(_snapshot());
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('db', raw);
      } else {
        final f = await _dbFile();
        await f.writeAsString(raw);
      }
    } catch (_) {
      // Stockage indisponible : l'app reste utilisable, sans persistance.
    }
    _programmerPush();
  }

  // ---------- Compte (synchronisation) ----------

  /// Envoi automatique vers le compte, quelques secondes apres la derniere
  /// modification (debounce). Echec silencieux : hors ligne, la prochaine
  /// modification retentera.
  void _programmerPush() {
    if (compteCle.isEmpty || serverUrl.isEmpty) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(seconds: 3), () async {
      try {
        await ApiKhompas(serverUrl).envoyerCompte(compteCle, exportJson());
      } catch (_) {
        // hors ligne / serveur indisponible : tant pis pour cette fois
      }
    });
  }

  Future<void> saveCompteCle(String cle) async {
    compteCle = cle.trim().toUpperCase();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('compteCle', compteCle);
    notifyListeners();
  }

  /// Dissocie l'appareil du compte (les donnees restent locales ET sur le
  /// serveur — seule la cle locale est oubliee).
  Future<void> deconnecterCompte() async {
    compteCle = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('compteCle');
    notifyListeners();
  }

  /// Connecte l'appareil a un compte existant : enregistre la cle et
  /// RESTAURE les donnees du compte (remplace les donnees locales).
  /// Retourne un resume, ou une explication si le compte est encore vide.
  Future<String> connecterCompte(String cle) async {
    final propre = cle.trim().toUpperCase();
    final data = await ApiKhompas(serverUrl).recupererCompte(propre);
    await saveCompteCle(propre);
    if (data == null || data.trim().isEmpty) {
      // Compte vide : on y envoie au contraire les donnees locales.
      _programmerPush();
      return 'compte encore vide — tes données locales vont y être envoyées';
    }
    return importJson(data);
  }

  /// Envoi immediat (bouton Reglages).
  Future<void> pousserCompte() async {
    await ApiKhompas(serverUrl).envoyerCompte(compteCle, exportJson());
  }

  /// Recuperation immediate (bouton Reglages) : remplace les donnees locales.
  Future<String> tirerCompte() async {
    final data = await ApiKhompas(serverUrl).recupererCompte(compteCle);
    if (data == null || data.trim().isEmpty) {
      throw Exception('aucune donnée sur ce compte pour le moment.');
    }
    return importJson(data);
  }

  void setCinqDemi(bool v) {
    cinqDemi = v;
    _touch();
  }

  Future<void> setOnboarded() async {
    onboarded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarded', true);
    notifyListeners();
  }

  // ---------- Sauvegarde / restauration ----------

  /// Contenu du fichier de sauvegarde partageable (meme format que le
  /// stockage interne, indente pour rester lisible).
  String exportJson() => const JsonEncoder.withIndent('  ').convert(_snapshot());

  /// Restaure une sauvegarde : REMPLACE toutes les donnees actuelles
  /// (la cle API n'est pas concernee). Tout est parse AVANT d'ecraser quoi
  /// que ce soit : en cas de fichier invalide, une exception est lancee et
  /// les donnees restent intactes. Retourne un petit resume.
  String importJson(String raw) {
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw Exception("ce fichier n'est pas un JSON valide.");
    }
    if (decoded is! Map<String, dynamic> ||
        (decoded['colles'] == null &&
            decoded['ds'] == null &&
            decoded['chapitres'] == null)) {
      throw Exception('ce fichier ne ressemble pas à une sauvegarde Khompas.');
    }
    try {
      final newColles = ((decoded['colles'] ?? []) as List)
          .map((e) => Colle.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      final newDs = ((decoded['ds'] ?? []) as List)
          .map((e) => Ds.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      final newChapitres = ((decoded['chapitres'] ?? []) as List)
          .map((e) => Chapitre.fromJson(e as Map<String, dynamic>))
          .toList();
      final newRoutines = ((decoded['routines'] ?? []) as List)
          .map((e) => Routine.fromJson(e as Map<String, dynamic>))
          .toList();
      final newDevoirs = ((decoded['devoirs'] ?? []) as List)
          .map((e) => Devoir.fromJson(e as Map<String, dynamic>))
          .toList();
      final newSeances = ((decoded['seances'] ?? []) as List)
          .map((e) => Seance.fromJson(e as Map<String, dynamic>))
          .toList();
      final newObjectifs = ((decoded['objectifs'] ?? {}) as Map)
          .map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
      final newDateConcours = decoded['dateConcours'] == null
          ? null
          : DateTime.tryParse(decoded['dateConcours'] as String);
      final newBilans = ((decoded['bilans'] ?? []) as List)
          .map((e) => Bilan.fromJson(e as Map<String, dynamic>))
          .toList();
      final newEvenements = ((decoded['evenements'] ?? []) as List)
          .map((e) => Evenement.fromJson(e as Map<String, dynamic>))
          .toList();
      final newSansCours = ((decoded['sansCours'] ?? []) as List)
          .map((e) => PlageSansCours.fromJson(e as Map<String, dynamic>))
          .toList();
      final newRefSemaineA = decoded['refSemaineA'] == null
          ? null
          : DateTime.tryParse(decoded['refSemaineA'] as String);
      final newMethode = (decoded['methodeTravail'] ?? methodeTravail) as String;
      final newFiliere = (decoded['filiere'] ?? filiere) as String;
      final newGroupe = ((decoded['groupe'] ?? groupe) as num).toInt();
      final newCodeClasse = (decoded['codeClasse'] ?? codeClasse) as String;
      final newCinqDemi = (decoded['cinqDemi'] ?? cinqDemi) as bool;
      final newPrios = ((decoded['prios'] ?? {}) as Map)
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
      colles = newColles;
      ds = newDs;
      chapitres = newChapitres;
      routines = newRoutines;
      devoirs = newDevoirs;
      seances = newSeances;
      objectifs = newObjectifs;
      dateConcours = newDateConcours;
      bilans = newBilans;
      evenements = newEvenements;
      sansCours = newSansCours;
      refSemaineA = newRefSemaineA;
      methodeTravail = newMethode;
      filiere = newFiliere;
      groupe = newGroupe;
      codeClasse = newCodeClasse;
      cinqDemi = newCinqDemi;
      prios = newPrios;
    } catch (_) {
      throw Exception('sauvegarde illisible ou incomplète — rien n\'a été modifié.');
    }
    _touch();
    return '${colles.length} khôlle(s), ${ds.length} DS, ${chapitres.length} chapitre(s)';
  }

  Future<void> saveApiKey(String key) async {
    apiKey = key.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('apiKey', apiKey);
    notifyListeners();
  }

  Future<void> saveServerUrl(String url) async {
    serverUrl = url.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('serverUrl', serverUrl);
    notifyListeners();
  }

  void setCodeClasse(String code) {
    codeClasse = code.trim().toUpperCase();
    _touch();
  }

  void _touch() {
    save();
    notifyListeners();
  }

  // ---------- Khôlles ----------

  /// Ajoute des colles en evitant les doublons exacts (meme matiere + meme debut).
  int addColles(List<Colle> nouvelles) {
    var added = 0;
    for (final c in nouvelles) {
      final doublon = colles.any((e) =>
          e.matiere.toLowerCase() == c.matiere.toLowerCase() &&
          e.start == c.start);
      if (!doublon) {
        colles.add(c);
        added++;
      }
    }
    colles.sort((a, b) => a.start.compareTo(b.start));
    _touch();
    return added;
  }

  void updateColle(Colle c) {
    final i = colles.indexWhere((e) => e.id == c.id);
    if (i >= 0) colles[i] = c;
    colles.sort((a, b) => a.start.compareTo(b.start));
    _touch();
  }

  void deleteColle(String id) {
    colles.removeWhere((e) => e.id == id);
    _touch();
  }

  // ---------- DS ----------

  void addDs(Ds d) {
    ds.add(d);
    ds.sort((a, b) => a.date.compareTo(b.date));
    _touch();
  }

  /// Ajoute un lot de DS (import planning) en evitant les doublons
  /// (meme matiere + meme jour). Retourne le nombre reellement ajoute.
  int addDsList(List<Ds> nouveaux) {
    var added = 0;
    for (final d in nouveaux) {
      final doublon = ds.any((e) =>
          e.matiere.toLowerCase() == d.matiere.toLowerCase() &&
          e.date.year == d.date.year &&
          e.date.month == d.date.month &&
          e.date.day == d.date.day);
      if (!doublon) {
        ds.add(d);
        added++;
      }
    }
    ds.sort((a, b) => a.date.compareTo(b.date));
    _touch();
    return added;
  }

  void updateDs(Ds d) {
    final i = ds.indexWhere((e) => e.id == d.id);
    if (i >= 0) ds[i] = d;
    _touch();
  }

  void deleteDs(String id) {
    ds.removeWhere((e) => e.id == id);
    _touch();
  }

  // ---------- Chapitres ----------

  void addChapitre(Chapitre c) {
    chapitres.add(c);
    _touch();
  }

  /// Ajoute un lot de chapitres (import du programme officiel) en evitant
  /// les doublons (meme matiere + meme nom). Retourne le nombre ajoute.
  int addChapitresList(List<Chapitre> nouveaux) {
    var added = 0;
    for (final c in nouveaux) {
      final doublon = chapitres.any((e) =>
          e.matiere.toLowerCase() == c.matiere.toLowerCase() &&
          e.nom.toLowerCase() == c.nom.toLowerCase());
      if (!doublon) {
        chapitres.add(c);
        added++;
      }
    }
    _touch();
    return added;
  }

  void updateChapitre(Chapitre c) {
    final i = chapitres.indexWhere((e) => e.id == c.id);
    if (i >= 0) chapitres[i] = c;
    _touch();
  }

  void deleteChapitre(String id) {
    chapitres.removeWhere((e) => e.id == id);
    _touch();
  }

  // ---------- Devoirs a rendre (DM / DNS) ----------

  void addDevoir(Devoir d) {
    devoirs.add(d);
    devoirs.sort((a, b) => a.dateRendu.compareTo(b.dateRendu));
    _touch();
  }

  void updateDevoir(Devoir d) {
    final i = devoirs.indexWhere((e) => e.id == d.id);
    if (i >= 0) devoirs[i] = d;
    devoirs.sort((a, b) => a.dateRendu.compareTo(b.dateRendu));
    _touch();
  }

  void deleteDevoir(String id) {
    devoirs.removeWhere((e) => e.id == id);
    _touch();
  }

  /// Devoirs pas encore rendus (les rendus recents restent visibles ailleurs).
  List<Devoir> devoirsARendre() =>
      devoirs.where((d) => !d.rendu).toList()
        ..sort((a, b) => a.dateRendu.compareTo(b.dateRendu));

  // ---------- Seances de travail (plan du soir coche) ----------

  void addSeance(String matiere, int minutes) {
    seances.add(Seance(matiere: matiere, date: DateTime.now(), minutes: minutes));
    // On ne garde que ~6 mois d'historique, largement assez pour les stats.
    final limite = DateTime.now().subtract(const Duration(days: 190));
    seances.removeWhere((s) => s.date.isBefore(limite));
    _touch();
  }

  /// Minutes travaillees cette semaine, par matiere (+ cle '' = total).
  Map<String, int> minutesSemaine() {
    final lundi = mondayOf(DateTime.now());
    final out = <String, int>{'': 0};
    for (final s in seances) {
      if (s.date.isBefore(lundi)) continue;
      out[s.matiere] = (out[s.matiere] ?? 0) + s.minutes;
      out[''] = out['']! + s.minutes;
    }
    return out;
  }

  // ---------- Objectifs (facultatifs, jamais culpabilisants) ----------

  void setObjectif(String matiere, double? obj) {
    if (obj == null) {
      objectifs.remove(matiere);
    } else {
      objectifs[matiere] = obj;
    }
    _touch();
  }

  // ---------- Mode revisions concours ----------

  void setDateConcours(DateTime? d) {
    dateConcours = d;
    _touch();
  }

  // ---------- Semaine type (routines) ----------

  void addRoutine(Routine r) {
    routines.add(r);
    _trierRoutines();
    _touch();
  }

  void updateRoutine(Routine r) {
    final i = routines.indexWhere((e) => e.id == r.id);
    if (i >= 0) routines[i] = r;
    _trierRoutines();
    _touch();
  }

  void deleteRoutine(String id) {
    routines.removeWhere((e) => e.id == id);
    _touch();
  }

  void _trierRoutines() {
    routines.sort((a, b) =>
        a.jour != b.jour ? a.jour.compareTo(b.jour) : a.debutMin.compareTo(b.debutMin));
  }

  /// Toutes les routines d'un jour de semaine (pour l'ecran d'edition,
  /// sans tenir compte du calendrier ni du roulement).
  List<Routine> routinesJourBrut(int weekday) =>
      routines.where((r) => r.jour == weekday).toList()
        ..sort((a, b) => a.debutMin.compareTo(b.debutMin));

  // ---------- Calendrier interne ----------

  /// La plage sans cours qui couvre [d], ou null (vacances, revisions...).
  PlageSansCours? plageSansCours(DateTime d) {
    for (final p in sansCours) {
      if (p.contient(d)) return p;
    }
    return null;
  }

  /// Semaine A ou B ? true = A. Sans reference definie, tout est "A".
  bool semaineEstA(DateTime d) {
    if (refSemaineA == null) return true;
    final diff = mondayOf(d).difference(mondayOf(refSemaineA!)).inDays;
    return (diff ~/ 7) % 2 == 0;
  }

  /// L'emploi du temps REEL d'une date : jour de semaine + roulement A/B
  /// + rien pendant les vacances / semaines de revisions.
  List<Routine> routinesLe(DateTime d) {
    if (plageSansCours(d) != null) return [];
    final estA = semaineEstA(d);
    return routines
        .where((r) =>
            r.jour == d.weekday &&
            (r.semaines == 0 ||
                (r.semaines == 1 && estA) ||
                (r.semaines == 2 && !estA)))
        .toList()
      ..sort((a, b) => a.debutMin.compareTo(b.debutMin));
  }

  void addPlageSansCours(PlageSansCours p) {
    sansCours.add(p);
    sansCours.sort((a, b) => a.debut.compareTo(b.debut));
    _touch();
  }

  void deletePlageSansCours(String id) {
    sansCours.removeWhere((p) => p.id == id);
    _touch();
  }

  void setRefSemaineA(DateTime? d) {
    refSemaineA = d;
    _touch();
  }

  Future<void> saveMethodeTravail(String methode) async {
    methodeTravail = methode;
    _touch();
  }

  // ---------- Evenements ponctuels ----------

  void addEvenement(Evenement e) {
    evenements.add(e);
    // Menage : on ne garde pas les evenements passes depuis > 60 jours.
    final limite = DateTime.now().subtract(const Duration(days: 60));
    evenements.removeWhere((x) => x.date.isBefore(limite));
    evenements.sort((a, b) => a.date != b.date
        ? a.date.compareTo(b.date)
        : a.debutMin.compareTo(b.debutMin));
    _touch();
  }

  void updateEvenement(Evenement e) {
    final i = evenements.indexWhere((x) => x.id == e.id);
    if (i >= 0) evenements[i] = e;
    evenements.sort((a, b) => a.date != b.date
        ? a.date.compareTo(b.date)
        : a.debutMin.compareTo(b.debutMin));
    _touch();
  }

  void deleteEvenement(String id) {
    evenements.removeWhere((x) => x.id == id);
    _touch();
  }

  /// Evenements ponctuels d'une date, tries par heure.
  List<Evenement> evenementsLe(DateTime d) => evenements
      .where((e) =>
          e.date.year == d.year &&
          e.date.month == d.month &&
          e.date.day == d.day)
      .toList()
    ..sort((a, b) => a.debutMin.compareTo(b.debutMin));

  // ---------- Bilans de journee ----------

  Bilan? bilanPour(DateTime jour, String routineId) {
    final j = DateTime(jour.year, jour.month, jour.day);
    for (final b in bilans) {
      if (b.routineId == routineId &&
          b.jour.year == j.year &&
          b.jour.month == j.month &&
          b.jour.day == j.day) {
        return b;
      }
    }
    return null;
  }

  /// Enregistre (ou remplace) le bilan d'un creneau, et si c'est un COURS
  /// avec un chapitre : le chapitre passe au moins en "vu en cours".
  void setBilan(Bilan b) {
    bilans.removeWhere((e) =>
        e.routineId == b.routineId &&
        e.jour.year == b.jour.year &&
        e.jour.month == b.jour.month &&
        e.jour.day == b.jour.day);
    bilans.add(b);
    // On garde ~2 mois d'historique, assez pour les stats a venir.
    final limite = DateTime.now().subtract(const Duration(days: 60));
    bilans.removeWhere((e) => e.jour.isBefore(limite));
    if (b.chapitreId != null) {
      final i = chapitres.indexWhere((c) => c.id == b.chapitreId);
      if (i >= 0 && chapitres[i].etape < 1) chapitres[i].etape = 1;
    }
    _touch();
  }

  void setPrio(String matiere, int p) {
    prios[matiere] = p;
    _touch();
  }

  void setProfil({required String filiere, required int groupe}) {
    this.filiere = filiere;
    this.groupe = groupe;
    _touch();
  }

  // ---------- Lectures pratiques ----------

  /// Toutes les matieres connues (colles + ds + chapitres), triees.
  List<String> get matieres {
    final s = <String>{};
    for (final c in colles) {
      if (c.matiere.isNotEmpty) s.add(c.matiere);
    }
    for (final d in ds) {
      if (d.matiere.isNotEmpty) s.add(d.matiere);
    }
    for (final c in chapitres) {
      if (c.matiere.isNotEmpty) s.add(c.matiere);
    }
    final l = s.toList()..sort();
    return l;
  }

  List<Colle> collesAvenir() {
    final now = DateTime.now();
    return colles.where((c) => c.end.isAfter(now)).toList();
  }

  Colle? prochaineColle() {
    final l = collesAvenir();
    return l.isEmpty ? null : l.first;
  }

  double? moyenneColles(String matiere) {
    final notes = colles
        .where((c) => c.matiere == matiere && c.note != null)
        .map((c) => c.note!)
        .toList();
    if (notes.isEmpty) return null;
    return notes.reduce((a, b) => a + b) / notes.length;
  }

  double? moyenneDs(String matiere) {
    final notes = ds
        .where((d) => d.matiere == matiere && d.note != null)
        .map((d) => d.note!)
        .toList();
    if (notes.isEmpty) return null;
    return notes.reduce((a, b) => a + b) / notes.length;
  }
}
