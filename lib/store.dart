import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Etat global de l'app, persiste dans un fichier JSON local.
/// (La cle API, plus sensible, vit dans SharedPreferences.)
class AppModel extends ChangeNotifier {
  static final AppModel instance = AppModel._();
  AppModel._();

  List<Colle> colles = [];
  List<Ds> ds = [];
  List<Chapitre> chapitres = [];
  String filiere = 'PCSI';
  int groupe = 1;
  // Priorite par matiere (1 a 3) : ponderation du plan de travail.
  Map<String, int> prios = {};

  String apiKey = '';
  bool loaded = false;

  // ---------- Persistance ----------

  Future<File> _dbFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/khompas.json');
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      apiKey = prefs.getString('apiKey') ?? '';
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
        filiere = (j['filiere'] ?? 'PCSI') as String;
        groupe = (j['groupe'] ?? 1) as int;
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
        'filiere': filiere,
        'groupe': groupe,
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
      final newFiliere = (decoded['filiere'] ?? filiere) as String;
      final newGroupe = ((decoded['groupe'] ?? groupe) as num).toInt();
      final newPrios = ((decoded['prios'] ?? {}) as Map)
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
      colles = newColles;
      ds = newDs;
      chapitres = newChapitres;
      filiere = newFiliere;
      groupe = newGroupe;
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

  void updateChapitre(Chapitre c) {
    final i = chapitres.indexWhere((e) => e.id == c.id);
    if (i >= 0) chapitres[i] = c;
    _touch();
  }

  void deleteChapitre(String id) {
    chapitres.removeWhere((e) => e.id == id);
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
